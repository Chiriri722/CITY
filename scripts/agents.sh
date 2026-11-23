#!/usr/bin/env bash
# Sourced by city.sh: the single catalog of supported agents and pinned releases.
# To bump an agent, change only its entry here (see README "유지보수").
# shellcheck disable=SC2034 # Every field is read by city.sh or environment.sh.

catalog=(
    codex opencode antigravity grok muse
    claude gemini qwen copilot amp crush cline kilo auggie droid qoder codebuddy
    continue forge jules kiro
    aider vibe openhands
)
# Releases look like 1.2.3, 1.4.3-R5018.1 or 0.0.1795449633-g4295dd.
version_pattern='[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.]*)?'

# npm registry tarball, verified by the registry's published SHA-512 integrity.
npm_release() {
    format=npm checksum=sha512 version="$2" digest="$3"
    url="https://registry.npmjs.org/$1/-/${1##*/}-$2.tgz"
}

# PyPI wheel, verified by PyPI's published SHA-256. Installed in its own venv.
wheel_release() {
    format=wheel checksum=sha256 version="$1" url="$2" digest="$3"
}

# Sets agent, binary, format, checksum, version, url, digest and member.
# The optional architecture (arm64|x64) matters only for downloads.
agent_info() {
    agent="$1" binary="$1" member=-
    local arm=false
    [[ "${2:-x64}" != arm64 ]] || arm=true
    case "$agent" in
        codex) npm_release @openai/codex 0.154.0 155ff1d4e1d762ffe27e37f79978fd4e14d301671464de9c18845046147190a34e3ee226bb5596d1cf1ebf5bd4904f57187f747449d81b5b418c8931462920d3 ;;
        opencode) npm_release opencode-ai 1.18.31 27de5f79e7de5b0b486b0de2af1efa5a3cd6720417c66b8798356986fb397a9f57df47c127a4fa6c5870e748bd2b1e74306ff13e7e70da969f5c87cdb5daf2f7 ;;
        antigravity)
            binary=agy format=archive checksum=sha512 version=1.3.1 member=antigravity
            if $arm; then
                url="https://storage.googleapis.com/antigravity-public/antigravity-cli/$version-4582356770750464/linux-arm/cli_linux_arm64.tar.gz"
                digest=c41b8cd8c526eb043fa0b019377ab8109190b547624f17f5255868ace79cd8e9195a60ac7b89478101127effbe049341c4108ed0ead4b160968704a8b79d8799
            else
                url="https://storage.googleapis.com/antigravity-public/antigravity-cli/$version-4582356770750464/linux-x64/cli_linux_x64.tar.gz"
                digest=3b8349d72678795baf8788481815e20d7acf3b80f9d2f867a607e712bc6be7fb18fd7d4fcf3aeee4ae593b0f469684c6d3497524f10a4c426a1a2bdec20b1f68
            fi
            ;;
        grok) npm_release @xai-official/grok 1.0.46 a973b89b224501008864d8cc25601a2744d35208b65ab4299d862dadd77d850f1361eccf1f4b25487058831a9e765c2070755da818a20d750b1e421d043ce4c9 ;;
        muse)
            format=binary checksum=sha256 version=1.4.3-R5018.1
            if $arm; then
                url="https://lookaside.facebook.com/lookaside/muse/download/?channel=muse&version=$version&file=muse-aarch64-linux"
                digest=6426c76a0081f20d60f6cad03308a147d79ce45758f1a89fd2713253cf475497
            else
                url="https://lookaside.facebook.com/lookaside/muse/download/?channel=muse&version=$version&file=muse-x86-linux"
                digest=e671790882bc88d65edb4ae0f713becf378ebf91011034ab75abebe3592dde4f
            fi
            ;;
        claude) npm_release @anthropic-ai/claude-code 2.1.330 290325ea48b12cc1874420d486450f79bb81870d77329c651f7fb5ed0cc7431e3414d55dd73dee14a512a905c1e7317dbcb406729a02ffcc167b9477e65b16bd ;;
        gemini) npm_release @google/gemini-cli 0.70.0 e608a5547f012366e34827fe5face01a94fbe5b2d6ccaf54a194b56a48da681c205a19b576eaf32a4342d4cdc56a6716e34628a95d0f0e2e2144222c6377fd4a ;;
        qwen) npm_release @qwen-code/qwen-code 0.28.4 287e0d1c2df16648e1837f248e6acc812084d3b162aa6d88404d205438e86d36ab8e0ae13cbebf878944381e041c03eb9f495a3c2abef5446d00ed44a86edc45 ;;
        copilot) npm_release @github/copilot 1.0.114 aa1894cd6180bb7bfd8d1314eb6605a6823fc7dfec4096f2954536acdacaa538094b0fa3457ede79ed1129ffd90bf15f38fb6e002a5758d050adfd3c5a154413 ;;
        amp) npm_release @sourcegraph/amp 0.0.1795449633-g4295dd db10df11d6d5750b9db1d61a64594237525f82004d7bddb7581a6f809574106e3e8d41c1b488f1432489aa59695148f1feabe1cff313802b7896f794c35d6b5a ;;
        crush) npm_release @charmland/crush 0.102.0 b24bf02d16c8a60130adf9dff5db91d6702b7928846a05f6d62b783c5cfe9a1d7633b0fad86443e7650527c900c7185e7d7cadf5db47fea2098388e8ef5914b2 ;;
        cline) npm_release cline 3.0.75 a4f4bdbe2c0bac537e82c7a902a3e8f2556fe70ae3a7c0b3541f546d11f057445ba6fb2b4521f1b681e8c4c376b6f38db8e2ef4c85a21183c4de1dca587a95d2 ;;
        kilo) npm_release @kilocode/cli 7.8.32 95b5becf8c0c8a83857a3789cb479211d6988fd05d3adfd051b40c54b166b9aa894a5b814b196624f48468708aaf053fecd5441f5c2703f2b5a353a5f675b3d8 ;;
        auggie) npm_release @augmentcode/auggie 1.2.2 4eeedf4e1ebc4a918e4c5dc787b48a4c13ede58b84f4da75ced95b2c1cc5664d065017aa34df5872ed1637a79f0837b1450cef63ed37606adf238840594440f4 ;;
        droid) npm_release @factory/cli 1.17.2 8616eff31a1d23560b79b7f24765438232fb0a0fd5508a92d4444d4339f85fb0de622dca6c89b8feeca4c9feac1050f29aafc830423a035049c3ea8c24dbfb7f ;;
        qoder) binary=qodercli; npm_release @qoder-ai/qodercli 1.1.96 0ee9302023e6cb67b58e5bb4f94484804223919904d95a9ee642a3c25853b18c8d90a0b59146fc9f5b149b9b2fbef50cf2992d3b444b48ad9277f1752ab5c3be ;;
        codebuddy) npm_release @tencent-ai/codebuddy-code 2.185.0 b41cd0eed68d3e63826ca2697fc77847f23906358624a93304511b63130290de9d9d67f620d487cfb6a737d002f61b2841958aefdfbee09a679a1a4d4ec190bc ;;
        continue) binary=cn; npm_release @continuedev/cli 1.5.47 82da5ec15dd1a08383f5dc93b4a2018b5498d1538746edc485eec2fe69a7b309be8f7e0c3f2adc42141a5a3fe6fa375f18ee1f34829dae018894bb28d542c317 ;;
        forge) npm_release forgecode 2.13.21 7f50a947625db90688d04c9feac406f8dd05e2925f04ce9582f081d93ed1a389381c84a0ffb2a01cc6ddaeb35c115b344a294f03fa2596d7c586edf4cd51d582 ;;
        jules)
            # The npm wrapper downloads this archive without a checksum; pin it directly.
            format=archive checksum=sha512 version=0.1.42 member=jules
            if $arm; then
                url="https://storage.googleapis.com/jules-cli/v$version/jules_external_v${version}_linux_arm64.tar.gz"
                digest=cd1dad1e1fdc8f0be7aad1828615a8d55a60ebc028c3c8ef173feaec34efcc546063f7c2d986f8d0e57c56f432fa0191745e520d83209269b8c46201d992aefa
            else
                url="https://storage.googleapis.com/jules-cli/v$version/jules_external_v${version}_linux_amd64.tar.gz"
                digest=d4cee780f023a8c57986fa3bf1bb770c7fb71e17ec85cd0f5d2faa45a9077cf8f05c7f1bce9f0dd5b6f9b8d678977696df0d7140f364e3cec3322c41a792a54d
            fi
            ;;
        kiro)
            # SHA-256 values are published in the vendor's release manifest.
            binary=kiro-cli format=archive checksum=sha256 version=3.5.0 member=kirocli/bin/kiro-cli
            if $arm; then
                url="https://desktop-release.q.us-east-1.amazonaws.com/$version/kirocli-aarch64-linux.tar.gz"
                digest=34444fee032944037282c762df4ff6929a51e827dd72d402cb7a8afbecb33e7f
            else
                url="https://desktop-release.q.us-east-1.amazonaws.com/$version/kirocli-x86_64-linux.tar.gz"
                digest=98f016b746b342d8337a0e937cabecc381037e2e920ea0ffaae649e51ef59d4e
            fi
            ;;
        aider) wheel_release 0.86.2 https://files.pythonhosted.org/packages/75/f7/e20749d9a510673e7adf910b005e3efe4ceaf9c194f1dd40d6931a3f34b9/aider_chat-0.86.2-py3-none-any.whl 64f6a0c66c9f4633ad9f479bca3e64ebcba02b9da03c6b604b74a44736b2416e ;;
        vibe)
            if $arm; then
                wheel_release 3.1.4 https://files.pythonhosted.org/packages/5f/29/04157bc49c0cd8d169efba8b74303fdd69314a866ccfaccc15590df2c40e/mistral_vibe-3.1.4-cp312-abi3-manylinux_2_28_aarch64.whl 6a5806aab9b0db312bfcc0dfe3a326846a520ff6dff2329697520b4b81d4cf82
            else
                wheel_release 3.1.4 https://files.pythonhosted.org/packages/49/4d/17de01bbd6b9bf40e89107759fa1a249a119f0fb6c2b7e08bf8aea51b549/mistral_vibe-3.1.4-cp312-abi3-manylinux_2_28_x86_64.whl e9bac639bbcdb0cdf3b79f26e6751d0c1651958a6401ac463a7e4c678a8a31ef
            fi
            ;;
        openhands) wheel_release 1.16.0 https://files.pythonhosted.org/packages/9b/af/5a3e5dca3c6e4beaac030bf944227e9efe54c40f3b3eca226d33d4680760/openhands-1.16.0-py3-none-any.whl e5495ddc76bff6ad8cf332b2e366c665f6735da31bc60fba9d430e19d11ffd3d ;;
        *) die "Unsupported agent: $agent. Supported: ${catalog[*]}" ;;
    esac
}
