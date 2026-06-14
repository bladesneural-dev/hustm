#!/bin/bash
set -e
source /venv/main/bin/activate 2>/dev/null || true

WORKSPACE=${WORKSPACE:-/workspace}
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

echo "=== FLUX.2-klein-9B + Z-Image Turbo Setup ==="

# === CUSTOM NODES ===
NODES=(
    "https://github.com/black-forest-labs/ComfyUI-Flux"
    "https://github.com/ltdrdata/ComfyUI-Manager"
    "https://github.com/yolain/ComfyUI-Easy-Use"
    "https://github.com/kijai/ComfyUI-KJNodes"
    "https://github.com/cubiq/ComfyUI_essentials"
    "https://github.com/rgthree/rgthree-comfy"
    "https://github.com/lquesada/ComfyUI-Inpaint-CropAndStitch"
    "https://github.com/chflame163/ComfyUI_LayerStyle"
    "https://github.com/Smirnov75/ComfyUI-mxToolkit"
    "https://github.com/ltdrdata/ComfyUI-Impact-Pack"
    "https://github.com/huchukato/ComfyUI-QwenVL-Mod"
    "https://github.com/bash-j/mikey_nodes"
    "https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes"
    "https://github.com/StableLlama/ComfyUI-basic_data_handling"
    "https://github.com/PGCRT/CRT-Nodes"
    "https://github.com/city96/ComfyUI-GGUF"
    "https://github.com/Fannovel16/comfyui_controlnet_aux"
)

# === PATHS ===
DIFFUSION_DIR="${COMFYUI_DIR}/models/diffusion_models"
TEXT_ENCODERS_DIR="${COMFYUI_DIR}/models/text_encoders"
VAE_DIR="${COMFYUI_DIR}/models/vae"
LORAS_DIR="${COMFYUI_DIR}/models/loras"

# === MODEL URLS ===
# FLUX.2
FLUX_URL="https://huggingface.co/black-forest-labs/FLUX.2-klein-9B/resolve/main/flux-2-klein-9b.safetensors"
QWEN_FP8_URL="https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors"
QWEN_FULL_URL="https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/qwen_3_8b.safetensors"
VAE_URL="https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors"

# Z-IMAGE TURBO (BF16)
ZIMAGE_MODEL_URL="https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors"
ZIMAGE_ENCODER_URL="https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b_fp8_mixed.safetensors"
ZIMAGE_VAE_URL="https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors"

# === HUGGINGFACE TOOLS ===
setup_hf_tools() {
    echo ""
    echo "🔧 Setting up HuggingFace tools..."
    pip install --no-cache-dir huggingface-hub huggingface 2>/dev/null || true
    
    export HF_HOME="${WORKSPACE}/.cache/huggingface"
    mkdir -p "$HF_HOME"
    
    if [[ -n "$HF_TOKEN" ]]; then
        huggingface-cli login --token "$HF_TOKEN" 2>/dev/null || true
    fi
    
    cat > /root/.bash_aliases << 'EOF'
alias hf-download='huggingface-cli download'
alias hf-cache='huggingface-cli scan-cache'
alias hf-clean='huggingface-cli delete-cache'
alias hf-whoami='huggingface-cli whoami'
alias dl-diffusion='huggingface-cli download --local-dir /workspace/ComfyUI/models/diffusion_models'
alias dl-encoder='huggingface-cli download --local-dir /workspace/ComfyUI/models/text_encoders'
alias dl-vae='huggingface-cli download --local-dir /workspace/ComfyUI/models/vae'
alias dl-lora='huggingface-cli download --local-dir /workspace/ComfyUI/models/loras'
alias models-size='du -sh /workspace/ComfyUI/models/*'
EOF
    source /root/.bash_aliases 2>/dev/null || true
    echo "✅ HF tools ready: hf-whoami, hf-cache, dl-diffusion, dl-encoder, dl-vae, dl-lora, models-size"
}

# === FUNCTIONS ===
clone_comfyui_if_needed() {
    if [[ ! -d "${COMFYUI_DIR}" ]]; then
        git clone https://github.com/comfyanonymous/ComfyUI.git "${COMFYUI_DIR}"
    fi
    cd "${COMFYUI_DIR}"
}

install_nodes() {
    mkdir -p "${COMFYUI_DIR}/custom_nodes"
    cd "${COMFYUI_DIR}/custom_nodes"
    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        if [[ -d "$dir" ]]; then
            (cd "$dir" && git pull --ff-only 2>/dev/null || git reset --hard origin/main)
        else
            git clone "$repo" "$dir" --recursive || { echo " [!] Failed: $repo"; continue; }
        fi
        [[ -f "$dir/requirements.txt" ]] && pip install --no-cache-dir -r "$dir/requirements.txt" 2>&1 | tail -n 2 || true
    done
}

download_with_auth() {
    local target_file="$1" url="$2"
    mkdir -p "$(dirname "$target_file")"
    [[ -f "$target_file" ]] && { echo "✅ Exists: $(basename "$target_file")"; return 0; }
    
    echo "→ Downloading: $(basename "$target_file")"
    local auth=""
    [[ -n "$HF_TOKEN" && "$url" =~ huggingface\.co ]] && auth="--header=\"Authorization: Bearer $HF_TOKEN\""
    
    if eval wget -nc --content-disposition --show-progress -e dotbytes=4M $auth -O "$target_file" "$url" 2>/dev/null; then
        echo "✅ Success: $(basename "$target_file")"
    else
        echo " [!] FAILED: $(basename "$target_file")"
        return 1
    fi
}

# === MAIN ===
echo "🔧 Setting up environment..."
clone_comfyui_if_needed

pip install --no-cache-dir transformers accelerate sentencepiece huggingface-hub einops safetensors opencv-python imageio diffusers 2>/dev/null || true

install_nodes
setup_hf_tools

echo ""
echo "📦 DOWNLOADING MODELS..."
echo "========================"

# FLUX.2
download_with_auth "${DIFFUSION_DIR}/flux-2-klein-9b.safetensors" "$FLUX_URL" || echo "⚠️ FLUX.2 failed"

download_with_auth "${TEXT_ENCODERS_DIR}/qwen_3_8b_fp8mixed.safetensors" "$QWEN_FP8_URL" || \
    download_with_auth "${TEXT_ENCODERS_DIR}/qwen_3_8b.safetensors" "$QWEN_FULL_URL" || echo " [!] Qwen encoder failed"

download_with_auth "${VAE_DIR}/flux2-vae.safetensors" "$VAE_URL" || echo " [!] FLUX VAE failed"

# Z-Image Turbo
echo ""
echo "📦 Z-Image Turbo (BF16)..."
download_with_auth "${DIFFUSION_DIR}/z_image_turbo_bf16.safetensors" "$ZIMAGE_MODEL_URL" || echo " [!] Z-Image model failed"

download_with_auth "${TEXT_ENCODERS_DIR}/qwen_3_4b_fp8_mixed.safetensors" "$ZIMAGE_ENCODER_URL" || echo " [!] Z-Image encoder failed"

download_with_auth "${VAE_DIR}/ae.safetensors" "$ZIMAGE_VAE_URL" || echo " [!] Z-Image VAE failed"

echo ""
echo "✅ PROVISIONING COMPLETE!"
echo "========================="
echo ""
echo "📁 Models:"
ls -lh "${DIFFUSION_DIR}"/*.safetensors 2>/dev/null
ls -lh "${TEXT_ENCODERS_DIR}"/*.safetensors 2>/dev/null
ls -lh "${VAE_DIR}"/*.safetensors 2>/dev/null
echo ""
echo "🔧 HF commands: hf-whoami, hf-cache, dl-diffusion <repo>, models-size"
echo "🚀 ComfyUI on port 18188"
