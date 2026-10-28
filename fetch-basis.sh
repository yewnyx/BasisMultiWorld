#!/bin/sh
# Fetches only the "Basis Server" folder of upstream Basis at BASIS_REF (commit, branch or tag)
# into ./basis, which the compose file builds the server image from. Nothing is forked.
#
# It also installs the WebSocket transport (web browsers, and native clients on networks that block
# UDP). Upstream doesn't ship that server package: it is fetched at WEBSOCKET_REF into the server's
# Packages folder and registered the way `basispm server-install` would, as a file: package, so the
# Docker build compiles it in without cloning anything itself.
set -eu
cd "$(dirname "$0")"
BASIS_REPO=${BASIS_REPO:-https://github.com/BasisVR/Basis.git}
[ -n "${BASIS_REF:-}" ] || BASIS_REF=$(sed -n 's/^BASIS_REF=//p' .env 2>/dev/null || true)
BASIS_REF=${BASIS_REF:-experimental-branch-major-changes}
WEBSOCKET_REPO=${WEBSOCKET_REPO:-https://github.com/dooly123/Basis-TCP-Transport-Package.git}
[ -n "${WEBSOCKET_REF:-}" ] || WEBSOCKET_REF=$(sed -n 's/^WEBSOCKET_REF=//p' .env 2>/dev/null || true)
WEBSOCKET_REF=${WEBSOCKET_REF:-62a4468432eb82c78ac744a7e78fca4bb91f7c8a}
if [ ! -d basis/.git ]; then
  git init -q basis
  git -C basis remote add origin "$BASIS_REPO"
  git -C basis config core.sparseCheckout true
  git -C basis config core.sparseCheckoutCone true
  mkdir -p basis/.git/info
  printf '/*\n!/*/\n/Basis Server/\n' > basis/.git/info/sparse-checkout
fi
git -C basis fetch -q --depth 1 --filter=blob:none origin "$BASIS_REF"
# -f drops the previous run's package registration below, which is then added again.
git -C basis checkout -q -f --detach FETCH_HEAD
echo "basis: $(git -C basis rev-parse --short HEAD) ($BASIS_REF)"

packages="basis/Basis Server/Packages"
package="$packages/com.basis.transport.websocket"
if [ ! -d "$package/.git" ]; then
  rm -rf "$package"
  git init -q "$package"
  git -C "$package" remote add origin "$WEBSOCKET_REPO"
fi
git -C "$package" fetch -q --depth 1 origin "$WEBSOCKET_REF"
git -C "$package" checkout -q -f --detach FETCH_HEAD
websocket_commit=$(git -C "$package" rev-parse --short HEAD)

# manifest.json is what basispm reads; packages-lock.props is what MSBuild builds from.
manifest="$packages/manifest.json"
awk '{ print } /"dependencies": *\{/ && !done { print "    \"com.basis.transport.websocket\": \"file:com.basis.transport.websocket\","; done = 1 }' \
  "$manifest" > "$manifest.tmp" && mv "$manifest.tmp" "$manifest"
lock="$packages/packages-lock.props"
[ "$(tail -n 1 "$lock" | tr -d '\r')" = "</Project>" ] || { echo "$lock: unexpected format, can't register the WebSocket package" >&2; exit 1; }
# The property suffix is the first 6 hex digits of sha256("com.basis.transport.websocket"), as basispm names it.
{
  sed '$d' "$lock"
  sed "s/@COMMIT@/$websocket_commit/" <<'EOF'
  <PropertyGroup>
    <BasisServerPackageRoot_com_basis_transport_websocket_4231fd Condition="'$(BasisServerPackageRoot_com_basis_transport_websocket_4231fd)' == ''">$(MSBuildThisFileDirectory)com.basis.transport.websocket/</BasisServerPackageRoot_com_basis_transport_websocket_4231fd>
  </PropertyGroup>
  <ItemGroup>
    <BasisServerPackage Include="com.basis.transport.websocket" Version="1.0.0" Source="file:com.basis.transport.websocket" Url="" Ref="" Commit="" SubPath="" LocalPath="com.basis.transport.websocket" Clone="" Root="$(BasisServerPackageRoot_com_basis_transport_websocket_4231fd)" Linked="$(BasisServerPackageLinked_com_basis_transport_websocket_4231fd)" />
    <BasisServerPackageModule Include="com.basis.transport.websocket" Path="Runtime" Assembly="BasisNetworkCore" Excludes="" />
    <BasisServerPackageModule Include="com.basis.transport.websocket" Path="Server~/BasisServerTests" Assembly="BasisServerTests" Excludes="" />
  </ItemGroup>
  <ItemGroup Condition="'$(MSBuildProjectName)' == 'BasisNetworkCore'">
    <Compile Include="$(BasisServerPackageRoot_com_basis_transport_websocket_4231fd)Runtime/**/*.cs" Exclude="$(BasisServerPackageRoot_com_basis_transport_websocket_4231fd)Runtime/**/obj/**;$(BasisServerPackageRoot_com_basis_transport_websocket_4231fd)Runtime/**/bin/**;$(BasisServerPackageRoot_com_basis_transport_websocket_4231fd)Runtime/**/.*/**;$(BasisServerPackageRoot_com_basis_transport_websocket_4231fd)Runtime/**/*~/**" LinkBase="Packages/com.basis.transport.websocket/Runtime" />
    <BasisServerPackageMissing Include="com.basis.transport.websocket" Root="$(BasisServerPackageRoot_com_basis_transport_websocket_4231fd)" Condition="!Exists('$(BasisServerPackageRoot_com_basis_transport_websocket_4231fd)package.json')" />
  </ItemGroup>
  <ItemGroup Condition="'$(MSBuildProjectName)' == 'BasisNetworkConsole'">
    <AssemblyMetadata Include="BasisServerPackage:com.basis.transport.websocket" Value="1.0.0 (@COMMIT@)" />
  </ItemGroup>
  <ItemGroup Condition="'$(MSBuildProjectName)' == 'BasisServerTests'">
    <Compile Include="$(BasisServerPackageRoot_com_basis_transport_websocket_4231fd)Server~/BasisServerTests/**/*.cs" Exclude="$(BasisServerPackageRoot_com_basis_transport_websocket_4231fd)Server~/BasisServerTests/**/obj/**;$(BasisServerPackageRoot_com_basis_transport_websocket_4231fd)Server~/BasisServerTests/**/bin/**;$(BasisServerPackageRoot_com_basis_transport_websocket_4231fd)Server~/BasisServerTests/**/.*/**;$(BasisServerPackageRoot_com_basis_transport_websocket_4231fd)Server~/BasisServerTests/**/*~/**" LinkBase="Packages/com.basis.transport.websocket/Server~/BasisServerTests" />
    <BasisServerPackageMissing Include="com.basis.transport.websocket" Root="$(BasisServerPackageRoot_com_basis_transport_websocket_4231fd)" Condition="!Exists('$(BasisServerPackageRoot_com_basis_transport_websocket_4231fd)package.json')" />
  </ItemGroup>
EOF
  echo '</Project>'
} > "$lock.tmp" && mv "$lock.tmp" "$lock"
echo "websocket transport: $websocket_commit"
