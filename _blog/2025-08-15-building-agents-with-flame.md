---
layout: blog
title: "Building AI Agents with Flame and OpenAI/LangChain"
date: 2025-08-15
author: "Klaus Ma"
categories: ["AI Agent", "Flame"]
tags: ["flame", "ai-agents", "distributed-computing", "kubernetes"]
---

The landscape of AI agent development is evolving quickly. Many frameworks promise rapid prototyping and production-ready deployments, yet teams still face familiar challenges: high task latency, suboptimal resource usage, and awkward integration patterns. Because agent workloads are inherently elastic, Flame is a natural fit to address these challenges.

## What Makes Flame Different?

Elastic workloads demand parallelism, efficient data sharing, and fast round-trips. Unlike batch jobs, they don’t rely on heavy inter-task communication. By introducing the concepts of Session, Application, and Executor, Flame provides a distributed computing platform tailored to elastic workloads at scale—such as AI agents.

### 1. Session-Based Isolation

In Flame, a Session is a group of tasks for an elastic workload. Clients can keep creating tasks until the session is closed. Within a session, tasks reuse the same executor to avoid cold starts and to share session-scoped data.

With session-based isolation:
- Data is not shared across sessions
- Executors are not reused across sessions, preventing data leakage

This makes it straightforward for agent frameworks like LangChain and CrewAI to support multi-tenancy and data isolation using Flame.

The following code demonstrates creating a service session and submitting a task to it. When creating a session via `flamepy.service.Session`, the client identifies the application (agent) to use and provides common data shared by all tasks in the session. We’ll introduce how to build and deploy an application in Flame in the following section.

```python
from flamepy.service import Session
from apis import MyContext, Question

# Each session is completely isolated
session = Session("openai-agent", ctx=MyContext(prompt="You are a weather forecaster."))

# First task of the session
output = session.invoke(Question(question="Who are you?"))
print(output.answer)

session.close()
```

### 2. Zero Cold Starts

Thanks to sessions, the executor stays warm for subsequent tasks in the same session, avoiding cold start latencies. If a session becomes idle, the executor remains available for a short period to absorb bursts; it’s released when the session closes or when the delayed-release timeout expires.

In addition to mapping one session to a single executor instance, Flame can scale out to multiple executors per session to increase parallelism when needed.

### 3. Elegantly Simple Python API

Flame’s Python SDK is designed with developer experience in mind. Building an AI agent typically starts with a `service.FlameInstance`, a typed entrypoint, and optional access to session context:

```python
from flamepy import service

ins = service.FlameInstance()

@ins.entrypoint
def my_agent(request: Question) -> Answer:
    ctx = ins.context()
    # Process the request with the session context.
    ...
    if ctx is not None:
        ins.update_context(ctx)
    return Answer(answer="...")

if __name__ == "__main__":
    ins.run()
```

API overview:
- **`service.FlameInstance`**: Owns the service process and entrypoint registration
- **`@ins.entrypoint`**: Handles individual requests with typed inputs and outputs
- **`ins.context()` / `ins.update_context()`**: Reads and updates session-scoped common data
- **`Session.invoke()` / `Session.run()`**: Sends work to the service synchronously or as a future with task notifications

Client-side APIs are equally simple. With a callback-based informer, the client receives state change notifications (e.g., pending, running).

```python
import flamepy
from flamepy.service import Session

class MyAgentTaskInformer(flamepy.TaskInformer):
    def on_update(self, task: flamepy.Task):
        pass
    
    def on_error(self):
        pass

# Each session is completely isolated
session = Session("openai-agent", ctx=MyContext(prompt="You are a weather forecaster."))

informer = MyAgentTaskInformer()

future = session.run(Question(question="Who are you?"), informer)
output = future.result()

session.close()
```

As a distributed system, Flame schedules tasks onto executors according to the scheduler’s algorithm. Client calls like `Session.invoke` and `Session.run` enqueue work for the matching application. Executors pick up work when scheduled.

### 4. Universal Integration: Framework-Agnostic

Flame’s general-purpose APIs integrate seamlessly with existing AI frameworks and tools. Whether you’re using LangChain, CrewAI, AutoGen, or others, Flame provides the execution layer:

```python
# LangChain Integration Example
from flamepy import service
from langchain.agents import create_agent
from langchain.messages import HumanMessage, SystemMessage
from langchain_deepseek import ChatDeepSeek

ins = service.FlameInstance()

llm = ChatDeepSeek(model="deepseek-chat", temperature=0, max_retries=2)
agent = create_agent(model=llm)

@ins.entrypoint
def my_agent(q: Question) -> Answer:
    messages = []

    ctx = ins.context()
    if ctx is not None and isinstance(ctx, SysPrompt):
        messages.append(SystemMessage(content=ctx.prompt))

    messages.append(HumanMessage(content=q.question))
    output = agent.invoke({"messages": messages})
    answer = output["messages"][-1].content

    return Answer(answer=answer)
```

This flexibility means:
- **No vendor lock-in**: Use your preferred AI libraries and models
- **Gradual migration**: Adopt Flame incrementally within existing projects
- **Best of both worlds**: Combine Flame’s infrastructure benefits with your favorite AI tools

## Real-World Example: OpenAI Agent

Let’s walk through a complete example that demonstrates Flame’s capabilities.

### The Agent Implementation

This example uses the OpenAI Agents SDK with a DeepSeek-compatible client:
- The service process creates a `service.FlameInstance` and registers a typed entrypoint
- The session’s common data provides the agent instructions and conversation history
- The entrypoint calls `ins.context()` before running the agent and `ins.update_context()` after the custom session has captured new messages

Flame guarantees that each task enters the registered entrypoint with the right session context. If the entrypoint raises an error, that task fails while other tasks and sessions remain isolated.

```python
import os
from typing_extensions import TypedDict
from openai import AsyncOpenAI
from agents import (
    Agent,
    Runner,
    function_tool,
    set_default_openai_api,
    set_default_openai_client,
    set_tracing_disabled,
)
from flamepy import service
from apis import MyContext, Question, Answer, MyCustomSession

ds_client = AsyncOpenAI(
    base_url="https://api.deepseek.com",
    api_key=os.getenv("DEEPSEEK_API_KEY"),
)
set_default_openai_client(ds_client)
set_tracing_disabled(True)
set_default_openai_api("chat_completions")

ins = service.FlameInstance()

class Location(TypedDict):
    lat: float
    long: float

@function_tool
async def fetch_weather(location: Location) -> str:
    return "sunny"

agent = Agent(
    name="openai-agent-example",
    model="deepseek-chat",
    tools=[fetch_weather],
)

@ins.entrypoint
async def my_agent(q: Question) -> Answer:
    ctx = ins.context()

    if ctx is not None and isinstance(ctx, MyContext):
        session = MyCustomSession(ctx)
        agent.instructions = ctx.prompt

        result = await Runner.run(agent, q.question, session=session)
        ctx.messages = session.history()
        ins.update_context(ctx)
    else:
        result = await Runner.run(agent, q.question)

    return Answer(answer=result.final_output)

# Run the agent
if __name__ == "__main__":
    ins.run()
```

### Deploy the Agent

After building the agent, deploy it to Flame. The deployment configuration assigns a name to the agent so clients can create sessions by name. It also specifies the agent’s startup command (arguments, environment variables, etc.).

In this example, the agent is named `openai-agent` and uses `uv` to launch, simplifying dependency management. For simplicity, the example is mounted directly into the `flame-executor-manager` container. We’ll discuss more advanced deployments (e.g., microVM) in future posts.

```yaml
# openai-agent.yaml
metadata:
  name: openai-agent
spec:
  command: /usr/bin/uv
  arguments:
    - run
    - /opt/examples/agents/openai/agent.py
  environments:
    DEEPSEEK_API_KEY: sk-xxxxxxxxxxxxxxxxx
```

Another benefit of `uv` is streamlined Python dependency management. `uv` supports declaring dependencies directly in script comments. This example uses the following to declare dependencies:

```python
# /// script
# dependencies = [
#   "openai",
#   "flamepy",
# ]
# [tool.uv.sources]
# flamepy = { path = "/usr/local/flame/sdk/python" }
# ///

# ... your script code ...
```

After preparing the deployment, use `flmctl` to register the agent:

```shell
$ flmctl register -f openai-agent.yaml
$ flmctl list -a
Name                Shim      State       Created        Command                       
flmping             Grpc      Enabled     03:36:51       /usr/local/flame/bin/flmping-service
flmexec             Grpc      Enabled     03:36:51       /usr/local/flame/bin/flmexec-service
flmtest             Log       Enabled     03:36:51       -                             
openai-agent        Grpc      Enabled     03:36:56       /usr/bin/uv                   
```

### The Client Usage

With the agent deployed, build a simple client to verify it. In this client, we create a session that asks the agent to act as a weather forecaster, then send a prompt asking the agent to introduce itself.

```python
from flamepy.service import Session
from apis import MyContext, Question

def main():
    # Create a session with initial context
    session = Session(
        "openai-agent",
        ctx=MyContext(prompt="You are a weather forecaster."),
    )
    
    # Send a task to the same session
    output = session.invoke(Question(question="Who are you?"))
    print(output.answer)

    session.close()

if __name__ == "__main__":
    main()
```

Run this client in a virtual environment on your desktop. You should see a response similar to the following:

```shell
(agent_example) $ python3 ./examples/agents/openai/client.py -m "Who are you?"
I’m your friendly weather forecaster assistant! 🌦️ I can help you check current weather conditions, forecasts, or answer any weather-related questions you have—whether it’s about rain, snow, storms, or just deciding if you need a jacket today.  
 
Want a forecast for your location or somewhere else? Just let me know! (Note: For real-time data, I may need you to enable location access or specify a place.)  
 
How can I brighten your weather knowledge today? ☀️🌧️
```

## Next / Roadmap

This post introduced how to run an AI agent with Flame at a high level. Upcoming posts will cover topics including, but not limited to:

1. Running generated scripts via Flame
2. Resource management in Flame
3. Updating common data within a session
4. Security considerations
5. Observability and evaluation
6. Performance best practices
