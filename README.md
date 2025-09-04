# XFLOPS Website

This repository contains the official website for XFLOPS, featuring comprehensive documentation for the Flame project - our distributed engine for AI Agents.

## About XFLOPS

[XFLOPS](http://github.com/xflops) is an organization that helps customers build cloud-native platforms for high-performance workloads including AI, BigData, and HPC. Our platform is built upon decades of experience in both batch and elastic workload management.

## About Flame

**Flame** is our flagship distributed engine for AI Agents, designed to handle the most demanding AI workloads with unprecedented efficiency and scalability. It provides the infrastructure and tools needed to deploy, manage, and scale AI applications across distributed environments.

### Key Features

- **Distributed AI Training**: Scale your AI model training across multiple nodes and clusters
- **Agent Orchestration**: Manage complex AI agent workflows and interactions
- **Resource Optimization**: Intelligent resource allocation for maximum efficiency
- **Fault Tolerance**: Built-in resilience and recovery mechanisms
- **Multi-Cloud Support**: Deploy across different cloud providers seamlessly
- **Heterogeneous Device Support**: Utilize GPUs, TPUs, and specialized accelerators

## Website Structure

This website is built with Jekyll and includes:

- **Homepage**: Introduction to XFLOPS and Flame project
- **Documentation**: Comprehensive guides and references
  - Getting Started Guide
  - Use Cases and Examples
  - User Guide and Best Practices
  - API Reference
  - Ecosystem Information
- **Blog**: Latest news, updates, and insights
- **Community**: Links to GitHub, Slack, and support channels

## Local Development

### Prerequisites

- Ruby 2.7 or later
- Jekyll 4.0 or later
- Bundler

### Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/xflops/xflops.github.io.git
   cd xflops.github.io
   ```

2. Install dependencies:
   ```bash
   bundle install
   ```

3. Start the development server:
   ```bash
   bundle exec jekyll serve
   ```

4. Open your browser and navigate to `http://localhost:4000`

### Building for Production

```bash
bundle exec jekyll build
```

The built site will be in the `_site` directory.

## Project Structure

```
.
├── _config.yml          # Jekyll configuration
├── _layouts/            # HTML layouts
├── _docs/               # Documentation pages
├── _blog/               # Blog posts
├── assets/              # CSS, JavaScript, and other assets
├── images/              # Images and logos
├── blog/                # Blog listing page
├── index.html           # Homepage
├── sitemap.xml          # Sitemap for SEO
├── robots.txt           # Robots file for crawlers
└── README.md            # This file
```

## Contributing

We welcome contributions to improve the website and documentation:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

### Documentation Guidelines

- Use clear, concise language
- Include code examples where appropriate
- Follow the existing style and format
- Test your changes locally before submitting

### Blog Post Guidelines

- Write informative, engaging content
- Include relevant tags and categories
- Use proper markdown formatting
- Add appropriate images and diagrams

## Deployment

The website is automatically deployed to GitHub Pages when changes are pushed to the main branch.

## Contact and Support

- **Email**: [support@xflops.io](mailto:support@xflops.io)
- **GitHub**: [http://github.com/xflops](http://github.com/xflops)
- **Slack**: [http://xflops.slack.com](http://xflops.slack.com)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with [Jekyll](https://jekyllrb.com/)
- Styled with modern CSS and responsive design
- Icons and graphics from various open-source sources

---

*Ready to explore Flame? Check out our [Getting Started Guide](/docs/getting-started/) and join our [community](http://xflops.slack.com)!*
