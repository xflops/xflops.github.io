#!/bin/sh
# curl -fsSL https://xflops.io/cluster/setup.sh | sh
# curl -fsSL https://xflops.io/cluster/setup.sh | sudo sh -s -- --join "$JOIN_TOKEN"
set +x
set -eu
umask 077

fail() { printf 'Flame Cluster: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "required command is missing: $1"; }
usage() {
    cat <<'USAGE'
usage: setup.sh [options]
       setup.sh --join TOKEN [options]
       setup.sh --join --token-file FILE [options]

  --version TAG             cluster release (default latest; immutable sha-* tags also work)
  --artifacts-dir DIR       use local release artifacts and SHA256SUMS instead of downloading
  --namespace NAME          management namespace (default flame-system); expected worker namespace with --join
  --cluster NAME            Flame base name (default flame; first resource flame-1); expected resource with --join
  --hostname HOST           gateway host (default active kubeconfig server host)
  --values FILE             optional additional flame-cluster chart values
  --flame-version TAG       override the first Flame runtime version (chart default latest)
  --image-tag TAG           operator/console/UI image tag (default release version)
  --endpoint HOST:PORT      worker FLM override (default kubeconfig IPv4:nodePort)
  --console-endpoint URL    direct console FLM endpoint (default the session-manager Service)
  --kubernetes-endpoint URL enrollment API override (default active kubeconfig server)
  --kubeconfig FILE         Kubernetes credentials for Helm installation
  --join TOKEN              install flmlet using an operator-issued join token
  --token-file FILE         read the join token from a file instead; never printed
  --worker NAME             worker name (default detected hostname)
  --address IPV4            worker LAN address (default detected private interface)
  --max-executors N          worker executor limit (default 10)
  --shims LIST              cri, host, or cri,host (default cri,host; SRE prepares runtimes)
  --manage-object-cache      let flmlet manage the worker object cache
  --prefix DIR              Flame installation directory (default /usr/local/flame)
  --systemd-dir DIR         systemd unit directory (default /etc/systemd/system)
  --adopt-existing          permit adoption of existing worker/service units
  -h, --help                show this help

Existing Kubernetes, cert-manager, Envoy Gateway/Gateway API, GatewayClass and
ClusterIssuer are SRE prerequisites. This script does not install them. Worker
mode requires Linux/systemd, root, Python 3, logrotate, and prepared workload runtimes/networking.
Flmlet uses upstream Flame setup to install systemd units, writes config, then restarts FEM.
Inline tokens can appear in process arguments; prefer --token-file on shared hosts.
USAGE
}

mode=cluster
version=latest
image_tag=
artifacts=
namespace=flame-system
namespace_set=0
cluster=flame
cluster_set=0
hostname=
values=
flame_version=latest
flame_version_set=0
endpoint=
console_endpoint=
kubernetes_endpoint=
kubeconfig=
token_file=
inline_join_token=
worker=
address=
max_executors=10
shims=cri,host
manage_cache=0
prefix=/usr/local/flame
systemd_dir=/etc/systemd/system
adopt=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --join)
            mode=worker; shift
            if [ "$#" -gt 0 ]; then
                case "$1" in
                    -*) ;;
                    *) [ -z "$inline_join_token" ] || fail 'provide only one join token'
                       inline_join_token="$1"; shift ;;
                esac
            fi ;;
        --adopt-existing) adopt=1; shift ;;
        --manage-object-cache) manage_cache=1; shift ;;
        -h|--help) usage; exit 0 ;;
        --version|--image-tag|--artifacts-dir|--namespace|--cluster|--hostname|--values|--flame-version|--endpoint|--console-endpoint|--kubernetes-endpoint|--kubeconfig|--token-file|--worker|--address|--max-executors|--shims|--prefix|--systemd-dir)
            [ "$#" -ge 2 ] && [ -n "$2" ] || fail "$1 requires a value"
            option="$1"; value="$2"; shift 2
            case "$option" in
                --version) version="$value" ;; --image-tag) image_tag="$value" ;;
                --artifacts-dir) artifacts="$value" ;; --namespace) namespace="$value"; namespace_set=1 ;;
                --cluster) cluster="$value"; cluster_set=1 ;; --hostname) hostname="$value" ;;
                --values) values="$value" ;; --flame-version) flame_version="$value"; flame_version_set=1 ;;
                --endpoint) endpoint="$value" ;; --console-endpoint) console_endpoint="$value" ;;
                --kubernetes-endpoint) kubernetes_endpoint="$value" ;; --kubeconfig) kubeconfig="$value" ;;
                --token-file) token_file="$value" ;; --worker) worker="$value" ;;
                --address) address="$value" ;; --max-executors) max_executors="$value" ;;
                --shims) shims="$value" ;;
                --prefix) prefix="$value" ;; --systemd-dir) systemd_dir="$value" ;;
            esac ;;
        *) fail 'unknown installer option (use --help)' ;;
    esac
done
[ -z "$inline_join_token" ] || [ -z "$token_file" ] || fail 'use either --join TOKEN or --join --token-file FILE, not both'
valid_tag() { printf '%s\n' "$1" | LC_ALL=C grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'; }
valid_name() { [ "${#1}" -le 63 ] && printf '%s\n' "$1" | LC_ALL=C grep -Eq '^[a-z0-9]([-a-z0-9]*[a-z0-9])?$'; }
valid_tag "$version" || fail 'invalid release tag'
valid_tag "$flame_version" || fail 'invalid Flame runtime version'
image_tag="${image_tag:-$version}"
valid_tag "$image_tag" || fail 'invalid image tag'
valid_name "$namespace" || fail 'invalid namespace'
valid_name "$cluster" && [ "${#cluster}" -le 32 ] || fail 'cluster name must be a DNS label of at most 32 characters'
[ -z "$values" ] || [ -f "$values" ] || fail '--values file does not exist'
[ -z "$artifacts" ] || [ -d "$artifacts" ] || fail '--artifacts-dir does not exist'
[ -z "$kubeconfig" ] || [ -r "$kubeconfig" ] || fail '--kubeconfig is not readable'
for tool in awk grep tar mktemp; do need "$tool"; done
if command -v sha256sum >/dev/null 2>&1; then digest_tool=sha256sum
elif command -v shasum >/dev/null 2>&1; then digest_tool=shasum
else fail 'sha256sum or shasum is required'; fi
[ -n "$artifacts" ] || need curl
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM
if [ -n "$inline_join_token" ]; then
    token_file="$work/join.token"
    printf '%s' "$inline_join_token" > "$token_file"
fi
unset inline_join_token

fetch() {
    download_asset="$1"
    if [ -n "$artifacts" ]; then
        [ -f "$artifacts/$download_asset" ] || fail "release artifact is missing: $download_asset"
        cp "$artifacts/$download_asset" "$work/$download_asset"
    else
        if [ "$version" = latest ]; then base=https://github.com/xflops/flame-cluster/releases/latest/download
        else base="https://github.com/xflops/flame-cluster/releases/download/$version"; fi
        curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 --max-time 180 "$base/$download_asset" -o "$work/$download_asset" || fail "could not download $download_asset"
    fi
}
verify() {
    verified_asset="$1"
    expected="$(awk -v name="$verified_asset" '$2 == name || $2 == "*" name { print $1 }' "$work/SHA256SUMS")"
    [ "${#expected}" -eq 64 ] && printf '%s\n' "$expected" | LC_ALL=C grep -Eq '^[0-9a-fA-F]{64}$' || fail "SHA256SUMS must contain exactly one checksum for $verified_asset"
    if [ "$digest_tool" = sha256sum ]; then actual="$(sha256sum "$work/$verified_asset" | awk '{print $1}')"
    else actual="$(shasum -a 256 "$work/$verified_asset" | awk '{print $1}')"; fi
    [ "$(printf '%s' "$actual" | tr A-F a-f)" = "$(printf '%s' "$expected" | tr A-F a-f)" ] || fail "checksum mismatch: $verified_asset"
}
extract() {
    archive="$1"
    tar -tzf "$work/$archive" > "$work/members" || fail "invalid release archive: $archive"
    while IFS= read -r member; do
        case "$member" in /*|..|../*|*/../*|*/..) fail "unsafe release archive: $archive" ;; esac
        case "$archive:$member" in
            flame-cluster-charts.tar.gz:charts|flame-cluster-charts.tar.gz:charts/|flame-cluster-charts.tar.gz:charts/*) ;;
            flmlet-*:bin|flmlet-*:bin/|flmlet-*:bin/flmlet|flmlet-*:LICENSE) ;;
            *) fail "unexpected release archive member: $member" ;;
        esac
    done < "$work/members"
    tar -tvzf "$work/$archive" > "$work/member-types" || fail "invalid release archive: $archive"
    awk 'substr($1,1,1) != "-" && substr($1,1,1) != "d" { exit 1 }' "$work/member-types" || fail 'release archives cannot contain links or special files'
    tar -xzf "$work/$archive" -C "$work" || fail "could not extract $archive"
}
kube() { if [ -n "$kubeconfig" ]; then kubectl --kubeconfig "$kubeconfig" "$@"; else kubectl "$@"; fi; }
helm_command() { if [ -n "$kubeconfig" ]; then helm --kubeconfig "$kubeconfig" "$@"; else helm "$@"; fi; }

if [ "$mode" = cluster ]; then
    [ -z "$token_file" ] && [ -z "$worker" ] || fail '--token-file and --worker require --join'
    for tool in helm kubectl python3; do need "$tool"; done
    kube_server="$(kube config view --minify -o 'jsonpath={.clusters[0].cluster.server}')" || fail 'cannot read the active kubeconfig server'
    python3 - "$kube_server" "$work/kube-host" "$work/worker-host" "$endpoint" "$work/ui-address" <<'PY'
import ipaddress
import json
import socket
import sys
from pathlib import Path
from urllib.parse import urlsplit

try:
    url = urlsplit(sys.argv[1])
    host = url.hostname
    if (url.scheme != 'https' or not host or url.username is not None or url.password is not None
            or url.path not in ('', '/') or url.query or url.fragment or ':' in host
            or not all(c.isascii() and (c.isalnum() or c in '.-') for c in host)
            or (url.port is not None and not 1 <= url.port <= 65535)):
        raise ValueError()
    Path(sys.argv[2]).write_text(host)
    address = socket.getaddrinfo(host, None, socket.AF_INET, socket.SOCK_STREAM)[0][4][0]
    ip = ipaddress.IPv4Address(address)
    frontend_ip = ip
    if sys.argv[4]:
        frontend_host, separator, frontend_port = sys.argv[4].rpartition(':')
        if not separator or not frontend_port.isascii() or not frontend_port.isdigit():
            raise ValueError()
        frontend_ip = ipaddress.IPv4Address(frontend_host)
        if not 30000 <= int(frontend_port) <= 32766:
            raise ValueError()
    networks = ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16')
    if not any(frontend_ip in ipaddress.IPv4Network(network) for network in networks):
        raise ValueError()
    Path(sys.argv[3]).write_text(str(frontend_ip))
    ui_ip = ip
    if ui_ip.is_unspecified or ui_ip.is_multicast or ui_ip.is_loopback or str(ui_ip) == '255.255.255.255':
        raise ValueError()
    Path(sys.argv[5]).write_text(str(ui_ip))
    allowed = list(dict.fromkeys(['localhost', '127.0.0.1', '::1', str(ui_ip), host]))
    Path(sys.argv[5]).with_name('api-allowed-hosts').write_text(json.dumps(allowed))
except (ValueError, OSError):
    sys.exit('Flame Cluster: invalid kubeconfig/UI address or worker endpoint; use HTTPS and a unicast UI IPv4, with an RFC 1918 frontend IPv4 and NodePort 30000..32766')
PY
    ui_address="$(cat "$work/ui-address")"
    api_allowed_hosts="$(cat "$work/api-allowed-hosts")"
    hostname="${hostname:-$(cat "$work/kube-host")}"
    kubernetes_endpoint="${kubernetes_endpoint:-$kube_server}"
    endpoint_host="$(cat "$work/worker-host")"
    printf '%s\n' "$hostname" | LC_ALL=C grep -Eq '^[a-zA-Z0-9]([-.a-zA-Z0-9]*[a-zA-Z0-9])?$' || fail '--hostname must be a DNS hostname or IPv4 address'
    kube get --raw /readyz >/dev/null || fail 'Kubernetes API is not ready'
    for crd in certificates.cert-manager.io clusterissuers.cert-manager.io gateways.gateway.networking.k8s.io backendtlspolicies.gateway.networking.k8s.io httproutes.gateway.networking.k8s.io referencegrants.gateway.networking.k8s.io envoyproxies.gateway.envoyproxy.io clienttrafficpolicies.gateway.envoyproxy.io; do
        kube get crd "$crd" >/dev/null 2>&1 || fail "SRE prerequisite is missing: $crd"
    done
    fetch SHA256SUMS
    fetch flame-cluster-charts.tar.gz
    verify flame-cluster-charts.tar.gz
    extract flame-cluster-charts.tar.gz
    for component in flame-operator flame-cluster flame-ui; do
        [ -f "$work/charts/$component/Chart.yaml" ] || fail "release chart is missing: $component"
    done
    # Share stream/List decoding between identity checks and namespace preparation.
    cat > "$work/rendered_objects.py" <<'PY_OBJECTS'
import json
from pathlib import Path


def read_objects(path):
    remaining = Path(path).read_text().lstrip()
    decoder = json.JSONDecoder()
    objects = []
    while remaining:
        obj, end = decoder.raw_decode(remaining)
        if not isinstance(obj, dict):
            raise ValueError('rendered Kubernetes object must be a JSON object')
        entries = obj.get('items') if obj.get('kind') == 'List' else [obj]
        if not isinstance(entries, list) or any(not isinstance(item, dict) for item in entries):
            raise ValueError('rendered Kubernetes List must contain JSON objects')
        objects.extend(entries)
        remaining = remaining[end:].lstrip()
    return objects
PY_OBJECTS
    # Render every component before the first persistent Kubernetes change.
    helm_command template flame-operator "$work/charts/flame-operator" --namespace "$namespace" --set-string "image.tag=$image_tag" > "$work/operator.yaml"
    set -- template flame-cluster "$work/charts/flame-cluster" --namespace "$namespace"
    [ -z "$values" ] || set -- "$@" --values "$values"
    set -- "$@" --set-string "flames[0].gateway.hostname=$hostname" --set-string "flames[0].endpointHost=$endpoint_host" --set-string "cluster.image.tag=$image_tag" --set-json "cluster.security.allowedHosts=$api_allowed_hosts"
    [ "$cluster_set" -eq 0 ] || set -- "$@" --set-string "flames[0].name=$cluster"
    [ "$flame_version_set" -eq 0 ] || set -- "$@" --set-string "flames[0].version=$flame_version"
    [ -z "$console_endpoint" ] || set -- "$@" --set-string "cluster.flame.endpoint=$console_endpoint"
    [ -z "$endpoint" ] || set -- "$@" --set-string "flames[0].endpoint=$endpoint"
    [ -z "$kubernetes_endpoint" ] || set -- "$@" --set-string "flames[0].kubernetesEndpoint=$kubernetes_endpoint"
    helm_command "$@" > "$work/cluster.yaml"
    awk '$1 == "className:" { gsub(/["\047]/,"",$2); print $2 }' "$work/cluster.yaml" | sort -u > "$work/gateway-classes"
    awk '$1 == "issuerName:" { gsub(/["\047]/,"",$2); print $2 }' "$work/cluster.yaml" | sort -u > "$work/issuers"
    [ -s "$work/gateway-classes" ] && [ -s "$work/issuers" ] || fail 'rendered Flame gateway prerequisites are missing'
    while IFS= read -r gateway_class; do
        valid_name "$gateway_class" || fail 'rendered gateway class is invalid'
        kube get gatewayclass "$gateway_class" >/dev/null || fail "SRE GatewayClass is missing: $gateway_class"
        kube wait "gatewayclass/$gateway_class" --for=condition=Accepted --timeout=120s >/dev/null || fail 'SRE GatewayClass is not accepted'
    done < "$work/gateway-classes"
    while IFS= read -r issuer; do
        valid_name "$issuer" || fail 'rendered cluster issuer is invalid'
        kube get clusterissuer "$issuer" >/dev/null || fail "SRE ClusterIssuer is missing: $issuer"
        kube wait "clusterissuer/$issuer" --for=condition=Ready --timeout=120s >/dev/null || fail 'SRE ClusterIssuer is not ready'
        kube -n "$namespace" get configmap "$issuer" -o json > "$work/ca-$issuer.json" || fail "SRE public trust ConfigMap is missing: $namespace/$issuer"
    done < "$work/issuers"
    helm_command template flame-ui "$work/charts/flame-ui" --namespace "$namespace" --set-string "image.tag=$image_tag" --set-string "consoleUpstream=cluster.$namespace.svc:3000" --set-string "service.externalIPs[0]=$ui_address" > "$work/ui.yaml"
    # Inspect stored identities before any mutation: new chart defaults must never
    # silently move an existing Flame away from its storage and worker identities.
    helm_command list --namespace "$namespace" --deployed --failed --pending --uninstalling --uninstalled --superseded --filter '^flame-cluster$' -o json > "$work/releases.json" || fail 'cannot inspect existing Flame Helm release'
    existing_release="$(python3 - "$work/releases.json" <<'PY_RELEASE'
import json
from pathlib import Path
import sys
try:
    releases = json.loads(Path(sys.argv[1]).read_text())
    if not isinstance(releases, list) or len(releases) > 1 or any(not isinstance(item, dict) or item.get('name') != 'flame-cluster' for item in releases):
        raise ValueError()
    print('yes' if releases else 'no')
except (ValueError, OSError):
    sys.exit('Flame Cluster: cannot parse existing Flame Helm release inventory')
PY_RELEASE
)" || fail 'cannot inspect existing Flame Helm release'
    if [ "$existing_release" = yes ]; then
        helm_command get manifest flame-cluster --namespace "$namespace" > "$work/previous-cluster.yaml" || fail 'cannot inspect existing Flame Helm manifest'
        kube create --dry-run=client --validate=false -f "$work/previous-cluster.yaml" -o json > "$work/previous-cluster.json" || fail 'cannot decode existing Flame Helm manifest'
        kube create --dry-run=client --validate=false -f "$work/cluster.yaml" -o json > "$work/proposed-cluster.json" || fail 'cannot decode proposed Flame Helm manifest'
        python3 - "$work" "$namespace" <<'PY_IDENTITIES'
from pathlib import Path
import re
import sys
work = Path(sys.argv[1])
sys.path.insert(0, str(work))
from rendered_objects import read_objects

def identities(path):
    result = set()
    for obj in read_objects(path):
        if obj.get('kind') != 'FlameCluster':
            continue
        metadata = obj.get('metadata', {})
        pair = (metadata.get('namespace'), metadata.get('name'))
        if any(not isinstance(value, str) or len(value) > 63 or not re.fullmatch(r'[a-z0-9]([-a-z0-9]*[a-z0-9])?', value) for value in pair) or pair in result:
            raise ValueError()
        result.add(pair)
    if not result:
        raise ValueError()
    return result

try:
    removed = identities(work / 'previous-cluster.json') - identities(work / 'proposed-cluster.json')
except (ValueError, TypeError, AttributeError, OSError):
    sys.exit('Flame Cluster: cannot validate existing and proposed Flame identities; no changes were made')
if removed:
    retained = ', '.join(f'{namespace}/{name}' for namespace, name in sorted(removed))
    sys.exit(f'Flame Cluster: upgrade would remove or move existing Flames: {retained}. No changes were made. Export `helm get values flame-cluster --namespace {sys.argv[2]} -o yaml > flame-values.yaml`, retain the FULL flames list and set each affected entry namespace explicitly to its existing namespace, then rerun setup.sh --values flame-values.yaml. Namespace migration requires a separate storage and credential migration.')
PY_IDENTITIES
    fi
    # Flame CRDs belong to this release; third-party CRDs remain SRE-owned.
    [ -d "$work/charts/flame-operator/crds" ] || fail 'operator CRDs are missing from the release'
    kube apply --server-side --field-manager=flame-cluster-setup -f "$work/charts/flame-operator/crds" >/dev/null
    kube wait crd/flameclusters.flame.xflops.io --for=condition=Established --timeout=120s >/dev/null
    # Resolve rendered object metadata after registering the Flame CRDs, without creating workloads.
    kube create --dry-run=client --validate=false -f "$work/cluster.yaml" -o json > "$work/cluster-objects.json"
    python3 - "$work" <<'PY_NAMESPACES'
import json
from pathlib import Path
import sys

work = Path(sys.argv[1])
json_source = 'rendered Kubernetes'
try:
    sys.path.insert(0, str(work))
    from rendered_objects import read_objects
    objects = read_objects(work / 'cluster-objects.json')
    namespaces = [obj for obj in objects if obj.get('kind') == 'Namespace']
    declared = {obj['metadata']['name'] for obj in namespaces}
    flames = [obj for obj in objects if obj.get('kind') == 'FlameCluster']
    if not namespaces or not flames:
        raise ValueError('no managed Flame namespaces were rendered')
    trust = []
    rows = []
    for obj in flames:
        ns, name = obj['metadata']['namespace'], obj['metadata']['name']
        issuer = obj['spec']['gateway']['issuerName']
        if ns not in declared or any(c in value for value in (ns, name, issuer) for c in '\t\r\n/'):
            raise ValueError('invalid rendered Flame metadata')
        json_source = f'SRE public CA trust for issuer {issuer}'
        source = json.loads((work / f'ca-{issuer}.json').read_text())
        ca = source['data']['ca.crt']
        if not isinstance(ca, str) or not ca.strip():
            raise ValueError('public CA trust is missing')
        trust.append({'apiVersion': 'v1', 'kind': 'ConfigMap', 'metadata': {'name': issuer, 'namespace': ns}, 'data': {'ca.crt': ca}})
        rows.append(f'{ns}\t{name}\t{issuer}\n')
    (work / 'namespaces.json').write_text(json.dumps({'apiVersion': 'v1', 'kind': 'List', 'items': namespaces}))
    (work / 'public-trust.json').write_text(json.dumps({'apiVersion': 'v1', 'kind': 'List', 'items': trust}))
    (work / 'flames.tsv').write_text(''.join(rows))
except json.JSONDecodeError as error:
    sys.exit(f'Flame Cluster: cannot parse {json_source} JSON: {error.msg} (line {error.lineno}, column {error.colno})')
except KeyError as error:
    sys.exit(f'Flame Cluster: rendered namespace configuration or SRE public CA trust is missing field {error.args[0]}')
except (ValueError, TypeError, OSError) as error:
    sys.exit(f'Flame Cluster: invalid rendered namespace configuration or SRE public CA trust: {error}')
PY_NAMESPACES
    # Pre-create the exact Helm-owned namespace metadata and copy public trust only.
    kube apply -f "$work/namespaces.json" >/dev/null
    kube apply -f "$work/public-trust.json" >/dev/null
    helm_command upgrade --install flame-operator "$work/charts/flame-operator" --namespace "$namespace" --create-namespace --skip-crds --set-string "image.tag=$image_tag" --wait --atomic --timeout 5m
    # Reuse the exact preflight-rendered cluster flags.
    set -- upgrade --install flame-cluster "$work/charts/flame-cluster" --namespace "$namespace"
    [ -z "$values" ] || set -- "$@" --values "$values"
    set -- "$@" --set-string "flames[0].gateway.hostname=$hostname" --set-string "flames[0].endpointHost=$endpoint_host" --set-string "cluster.image.tag=$image_tag" --set-json "cluster.security.allowedHosts=$api_allowed_hosts"
    [ "$cluster_set" -eq 0 ] || set -- "$@" --set-string "flames[0].name=$cluster"
    [ "$flame_version_set" -eq 0 ] || set -- "$@" --set-string "flames[0].version=$flame_version"
    [ -z "$console_endpoint" ] || set -- "$@" --set-string "cluster.flame.endpoint=$console_endpoint"
    [ -z "$endpoint" ] || set -- "$@" --set-string "flames[0].endpoint=$endpoint"
    [ -z "$kubernetes_endpoint" ] || set -- "$@" --set-string "flames[0].kubernetesEndpoint=$kubernetes_endpoint"
    helm_command "$@" --wait --atomic --timeout 5m
    while IFS="$(printf '\t')" read -r flame_namespace flame_name flame_issuer; do
        kube -n "$flame_namespace" wait "flamecluster/$flame_name" --for=condition=Ready --timeout=15m
        printf 'Flame %s/%s is ready.\n' "$flame_namespace" "$flame_name"
    done < "$work/flames.tsv"
    helm_command upgrade --install flame-ui "$work/charts/flame-ui" --namespace "$namespace" --set-string "image.tag=$image_tag" --set-string "consoleUpstream=cluster.$namespace.svc:3000" --set-string "service.externalIPs[0]=$ui_address" --wait --atomic --timeout 5m
    printf 'Flame management service installed in %s.\n' "$namespace"
    printf 'Console: http://%s/\n' "$ui_address"
    exit 0
fi

# Enroll the host and install flmlet; flmlet owns FEM installation and configuration.
need python3
need systemctl
[ "$(uname -s)" = Linux ] || fail 'worker installation requires Linux'
[ "$(id -u)" = 0 ] || fail 'worker installation requires root'
[ -n "$token_file" ] && [ -r "$token_file" ] || fail '--join requires a token or readable --token-file'
[ -z "$kubeconfig" ] || fail 'worker enrollment uses --token-file, not --kubeconfig'
if printf '%s' "$prefix$systemd_dir" | LC_ALL=C grep -q '[[:cntrl:]]'; then fail 'prefix and systemd directory cannot contain control characters'; fi
case "$prefix:$systemd_dir" in *'"'*|*'\'*|*'$'*|*'%'*) fail 'prefix and systemd directory contain unsupported characters' ;; esac
case "$prefix" in /*) ;; *) fail '--prefix must be absolute' ;; esac
case "$systemd_dir" in /*) ;; *) fail '--systemd-dir must be absolute' ;; esac
# Decode bootstrap credentials into temporary files only. No bootstrap JWT is retained.
cat > "$work/enrollment.py" <<'PY_ENROLL'
import base64
import binascii
import fcntl
import http.client
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import socket
import ssl
import stat
import struct
import sys
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, build_opener, HTTPSHandler, HTTPRedirectHandler


def require(value, message):
    if not value:
        raise ValueError(message)


def name(value, limit, dots=False):
    require(isinstance(value, str) and len(value) <= limit, 'invalid enrollment identity')
    parts = value.split('.') if dots else [value]
    require(all(re.fullmatch(r'[a-z0-9](?:[-a-z0-9]*[a-z0-9])?', part) and len(part) <= 63 for part in parts), 'invalid enrollment identity')


def private_address(value):
    address = ipaddress.IPv4Address(value)
    require(any(address in network for network in (ipaddress.IPv4Network('10.0.0.0/8'), ipaddress.IPv4Network('172.16.0.0/12'), ipaddress.IPv4Network('192.168.0.0/16'))), 'worker address must be a private LAN IPv4 address; use --address')
    return str(address)


def detect_address(server):
    target = urlsplit(server)
    for destination in ((target.hostname, target.port or 443), ('192.0.2.1', 9)):
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
                probe.connect(destination)
                return private_address(probe.getsockname()[0])
        except (OSError, ValueError):
            pass
    candidates = set()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        for _, interface in socket.if_nameindex():
            if interface.startswith(('lo', 'docker', 'br-', 'veth', 'virbr', 'cni', 'flannel')):
                continue
            try:
                packed = struct.pack('256s', interface.encode()[:15])
                address = socket.inet_ntoa(fcntl.ioctl(probe.fileno(), 0x8915, packed)[20:24])
                candidates.add(private_address(address))
            except (OSError, ValueError):
                pass
    require(len(candidates) == 1, 'cannot select one private LAN address; use --address')
    return candidates.pop()


def config(value, namespaces):
    require(isinstance(value, str), 'invalid embedded kubeconfig')
    result = json.loads(value)
    require(isinstance(result, dict) and result.get('apiVersion') == 'v1' and result.get('kind') == 'Config', 'invalid embedded kubeconfig')
    for key in ('clusters', 'contexts', 'users'):
        require(isinstance(result.get(key), list) and len(result[key]) == 1, 'enrollment requires one scoped identity')
    cluster, context, user = result['clusters'][0], result['contexts'][0], result['users'][0]
    details, identity, selected = cluster['cluster'], user['user'], context['context']
    require(all(isinstance(item, dict) for item in (details, identity, selected)), 'invalid kubeconfig records')
    require(set(identity) == {'token'} and isinstance(identity['token'], str) and identity['token'], 'kubeconfig must use only its scoped token')
    require(set(details) == {'server', 'certificate-authority-data'}, 'kubeconfig requires explicit server and CA trust')
    url = urlsplit(details['server'])
    require(url.scheme == 'https' and url.hostname and not url.username and not url.password and not url.query and not url.fragment and url.path in ('', '/'), 'API server must be an HTTPS authority')
    require(url.port is None or 1 <= url.port <= 65535, 'invalid API server port')
    trust = base64.b64decode(details['certificate-authority-data'], validate=True).decode('ascii')
    tls = ssl.create_default_context(cadata=trust)
    require(selected.get('namespace') in namespaces and selected.get('cluster') == cluster['name'] and selected.get('user') == user['name'] and result.get('current-context') == context['name'], 'kubeconfig context does not match its scope')
    require(set(result) <= {'apiVersion', 'kind', 'clusters', 'contexts', 'users', 'current-context', 'preferences'}, 'unsupported kubeconfig settings')
    return result, details['server'].rstrip('/'), identity['token'], tls


def private_write(path, value):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'w') as output:
        output.write(value)


def decode(arguments):
    source, directory, namespace, explicit_namespace, cluster, explicit_cluster, worker, address, maximum, cache, shims = arguments
    raw = Path(source).read_bytes()
    require(len(raw) <= 1024 * 1024, 'join token is too large')
    opaque = raw.strip().decode('ascii')
    envelope = json.loads(base64.b64decode(opaque, validate=True))
    require(isinstance(envelope, dict) and set(envelope) == {'namespace', 'cluster', 'serviceNamespace', 'service', 'kubeconfig'}, 'invalid join token fields')
    for key, limit in (('namespace', 63), ('cluster', 32), ('serviceNamespace', 63), ('service', 63)):
        name(envelope[key], limit)
    require(explicit_namespace != '1' or namespace == envelope['namespace'], 'join namespace does not match --namespace')
    require(explicit_cluster != '1' or cluster == envelope['cluster'], 'join cluster does not match --cluster')
    worker = worker or socket.gethostname().lower()
    name(worker, 253, True)
    _, server, _, _ = config(envelope['kubeconfig'], {envelope['namespace'], envelope['serviceNamespace']})
    maximum = int(maximum)
    require(1 <= maximum <= 2147483647, '--max-executors must be a positive 32-bit integer')
    require(cache in ('0', '1'), 'invalid object cache setting')
    shims = [value.strip() for value in shims.split(',')]
    require(shims and len(set(shims)) == len(shims) and all(value in ('cri', 'host') for value in shims), '--shims must contain unique cri and/or host values')
    address = private_address(address) if address else detect_address(server)
    directory = Path(directory)
    private_write(directory / 'bootstrap.json', json.dumps(envelope))
    private_write(directory / 'opaque-token', opaque)
    private_write(directory / 'join-request.json', json.dumps({'namespace': envelope['namespace'], 'cluster': envelope['cluster'], 'worker': worker, 'address': address, 'maxExecutors': maximum, 'manageObjectCache': cache == '1', 'shims': shims}))
    private_write(directory / 'namespace', envelope['namespace'])
    private_write(directory / 'worker', worker)


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, url):
        return None


class Rejected(Exception):
    def __init__(self, status):
        self.status = status


def enroll(arguments):
    directory, prefix = map(Path, arguments)
    envelope = json.loads((directory / 'bootstrap.json').read_text())
    payload = json.loads((directory / 'join-request.json').read_text())
    _, server, credential, tls = config(envelope['kubeconfig'], {envelope['namespace'], envelope['serviceNamespace']})
    url = f"{server}/api/v1/namespaces/{envelope['serviceNamespace']}/services/http:{envelope['service']}:8081/proxy/join"
    state = prefix / 'conf' / 'flmlet'
    created_directories = []
    for candidate in (*reversed(prefix.parents), prefix, prefix / 'conf', state):
        try:
            candidate.mkdir(mode=0o700 if candidate in (prefix / 'conf', state) else 0o755)
            created_directories.append(candidate)
        except FileExistsError:
            require(candidate.is_dir(), 'flmlet state path is not a directory')
    lock_path = state / 'enrollment.lock'
    new_lock = not lock_path.exists()
    lock = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
    new_key = False
    accepted = False
    key_path = state / 'enrollment-key'
    try:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('worker enrollment is already in progress on this host') from None
        if key_path.exists():
            require(stat.S_ISREG(key_path.lstat().st_mode) and not stat.S_IMODE(key_path.stat().st_mode) & 0o077, 'enrollment key must be a private regular file')
            enrollment_key = key_path.read_text().strip()
            require(re.fullmatch(r'[a-f0-9]{64}', enrollment_key), 'invalid existing enrollment key')
        else:
            enrollment_key = secrets.token_hex(32)
            descriptor, temporary = tempfile.mkstemp(prefix='.enrollment-key.', dir=state)
            try:
                with os.fdopen(descriptor, 'w') as output:
                    output.write(enrollment_key)
                    output.flush()
                    os.fsync(output.fileno())
                os.link(temporary, key_path)
                new_key = True
            finally:
                Path(temporary).unlink()
        payload.update(enrollmentKey=enrollment_key, token=(directory / 'opaque-token').read_text())
        encoded = json.dumps(payload).encode()
        opener = build_opener(HTTPSHandler(context=tls), NoRedirect())
        deadline = time.monotonic() + 180
        while True:
            request = Request(url, data=encoded, headers={'Authorization': f'Bearer {credential}', 'Content-Type': 'application/json', 'User-Agent': 'Flame-Cluster-Installer'}, method='POST')
            try:
                with opener.open(request, timeout=10) as response:
                    status = response.status
                    body = response.read(1024 * 1024 + 1)
                require(len(body) <= 1024 * 1024, 'enrollment response is too large')
            except HTTPError as error:
                if error.code < 500:
                    raise Rejected(error.code) from None
                raise ValueError('worker enrollment service unavailable; retry with the same host state') from None
            except (URLError, OSError, http.client.HTTPException):
                raise ValueError('worker enrollment transport failed; retry with the same host state') from None
            if status == 200:
                accepted = True
                result = json.loads(body)
                require(isinstance(result, dict) and set(result) == {'namespace', 'worker', 'kubeconfig'} and result['namespace'] == payload['namespace'] and result['worker'] == payload['worker'], 'enrollment response does not match this worker')
                durable, _, _, _ = config(result['kubeconfig'], {payload['namespace']})
                private_write(directory / 'kubeconfig', json.dumps(durable))
                return
            require(status == 202, 'unexpected enrollment response')
            accepted = True
            require(time.monotonic() < deadline, 'worker enrollment is pending; retry with the same host state')
            time.sleep(2)
    except Rejected as error:
        if not accepted:
            if new_key:
                key_path.unlink(missing_ok=True)
            if new_lock:
                lock_path.unlink(missing_ok=True)
            for candidate in reversed(created_directories):
                try:
                    candidate.rmdir()
                except OSError:
                    pass
        raise ValueError(f'worker enrollment rejected (HTTP {error.status})') from None
    finally:
        os.close(lock)


try:
    action, *arguments = sys.argv[1:]
    if action == 'decode':
        decode(arguments)
    elif action == 'enroll':
        enroll(arguments)
    else:
        raise ValueError('invalid enrollment operation')
except (ValueError, TypeError, KeyError, AttributeError, OSError, binascii.Error):
    # Never echo token data, credential-bearing responses, or HTTP request bodies.
    error = sys.exc_info()[1]
    safe = str(error) if isinstance(error, ValueError) and str(error).startswith(('worker enrollment ', 'cannot select one private LAN address', '--max-executors ', '--shims ', 'join namespace ', 'join cluster ', 'worker address ')) else 'invalid or mismatched join token or worker state'
    print(f'Flame Cluster: {safe}', file=sys.stderr)
    sys.exit(1)
PY_ENROLL
python3 "$work/enrollment.py" decode "$token_file" "$work" "$namespace" "$namespace_set" "$cluster" "$cluster_set" "$worker" "$address" "$max_executors" "$manage_cache" "$shims"
namespace="$(cat "$work/namespace")"
worker="$(cat "$work/worker")"
case "$(uname -m)" in x86_64|amd64) architecture=amd64 ;; aarch64|arm64) architecture=arm64 ;; *) fail 'unsupported worker CPU architecture' ;; esac
asset="flmlet-linux-$architecture.tar.gz"
fetch SHA256SUMS
fetch "$asset"
verify "$asset"
extract "$asset"
[ -x "$work/bin/flmlet" ] || fail 'flmlet is missing from the release archive'
if [ -e "$systemd_dir/flmlet.service" ]; then
    if ! grep -F '# Managed by Flame Cluster setup.sh' "$systemd_dir/flmlet.service" >/dev/null \
        || ! grep -F -- "--worker \"$worker\" --namespace \"$namespace\"" "$systemd_dir/flmlet.service" >/dev/null; then
        [ "$adopt" -eq 1 ] || fail 'existing flmlet.service has another owner or worker identity; use --adopt-existing explicitly'
    fi
fi
python3 "$work/enrollment.py" enroll "$work" "$prefix"
set -- --worker "$worker" --namespace "$namespace" --prefix "$prefix" --kubeconfig "$work/kubeconfig" --systemd-dir "$systemd_dir" --check
[ "$adopt" -eq 0 ] || set -- "$@" --adopt-existing
"$work/bin/flmlet" "$@" >/dev/null || fail 'flmlet preflight failed; enrollment state retained for retry'
# Staging completed. Replace only installer-owned files and retain credentials mode 0600.
install -d -m 0755 "$prefix/bin" "$systemd_dir"
install -d -m 0700 "$prefix/conf/flmlet"
install -m 0755 "$work/bin/flmlet" "$prefix/bin/flmlet.new"
mv "$prefix/bin/flmlet.new" "$prefix/bin/flmlet"
install -m 0600 "$work/kubeconfig" "$prefix/conf/flmlet/kubeconfig.new"
mv "$prefix/conf/flmlet/kubeconfig.new" "$prefix/conf/flmlet/kubeconfig"
set -- --worker "$worker" --namespace "$namespace" --prefix "$prefix" --kubeconfig "$prefix/conf/flmlet/kubeconfig" --systemd-dir "$systemd_dir" --configure
[ "$adopt" -eq 0 ] || set -- "$@" --adopt-existing
"$prefix/bin/flmlet" "$@" >/dev/null || fail 'flmlet configuration failed; retry this host with the same enrollment state'
{
    printf '%s\n' '# Managed by Flame Cluster setup.sh' '[Unit]' 'Description=Flame worker reconciliation' 'Wants=network-online.target' 'After=network-online.target' 'StartLimitIntervalSec=0' '' '[Service]' 'Type=simple' 'User=root' 'UMask=0077'
    printf 'ExecStart="%s/bin/flmlet" --worker "%s" --namespace "%s" --prefix "%s" --kubeconfig "%s/conf/flmlet/kubeconfig" --systemd-dir "%s"' "$prefix" "$worker" "$namespace" "$prefix" "$prefix" "$systemd_dir"
    [ "$adopt" -eq 0 ] || printf ' --adopt-existing'
    printf '\n%s\n' 'Restart=always' 'RestartSec=5' 'NoNewPrivileges=true' '' '[Install]' 'WantedBy=multi-user.target'
} > "$work/flmlet.service"
install -m 0644 "$work/flmlet.service" "$systemd_dir/flmlet.service"
systemctl daemon-reload
systemctl enable flmlet.service
systemctl restart flmlet.service
printf 'Flmlet installed for %s/%s.\n' "$namespace" "$worker"
