#!/bin/bash
set -e
source /venv/main/bin/activate 2>/dev/null || true

WORKSPACE=${WORKSPACE:-/workspace}
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

echo "=== FLUX.2-klein-9B + Qwen3-8B + Z-Image Turbo (BF16) + HF Tools ==="

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
)

# === PATHS ===
DIFFUSION_DIR="${COMFYUI_DIR}/models/diffusion_models"
TEXT_ENCODERS_DIR="${COMFYUI_DIR}/models/text_encoders"
VAE_DIR="${COMFYUI_DIR}/models/vae"
LLM_DIR="${COMFYUI_DIR}/models/LLM"
LORAS_DIR="${COMFYUI_DIR}/models/loras"
HF_CACHE_DIR="${WORKSPACE}/.cache/huggingface"

# === MODEL URLS ===
# FLUX.2
FLUX_URL="https://huggingface.co/black-forest-labs/FLUX.2-klein-9B/resolve/main/flux-2-klein-9b.safetensors"
QWEN_FP8_URL="https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors"
QWEN_FULL_URL="https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/qwen_3_8b.safetensors"
VAE_URL="https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors"
QWEN_GGUF_URL="https://huggingface.co/mradermacher/Qwen3-8B-heretic-GGUF/resolve/main/Qwen3-8B-heretic.Q8_0.gguf"

# Z-IMAGE TURBO (BF16)
ZIMAGE_MODEL_URL="https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors"
ZIMAGE_ENCODER_URL="https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b_fp8_mixed.safetensors"
ZIMAGE_VAE_URL="https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors"
ZIMAGE_LORA_URL="https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/loras/z_image_turbo_distill_patch_lora_bf16.safetensors"

# === FUNCTIONS ===

clone_comfyui_if_needed() {
    if [[ ! -d "${COMFYUI_DIR}" ]]; then
        echo "→ Cloning ComfyUI..."
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
            echo "→ Updating $dir"
            (cd "$dir" && git pull --ff-only 2>/dev/null || git reset --hard origin/main)
        else
            echo "→ Cloning $dir"
            if ! git clone "$repo" "$dir" --recursive; then
                echo " [!] Failed to clone $repo"
                continue
            fi
        fi
        
        if [[ -f "$dir/requirements.txt" ]]; then
            echo "→ Installing requirements for $dir"
            pip install --no-cache-dir -r "$dir/requirements.txt" 2>&1 | tail -n 3
        fi
    done
}

download_with_auth() {
    local target_file="$1"
    local url="$2"
    local target_dir="$(dirname "$target_file")"
    
    mkdir -p "$target_dir"
    
    if [[ -f "$target_file" ]]; then
        echo "✅ Exists: $(basename "$target_file")"
        return 0
    fi
    
    echo "→ Downloading: $(basename "$target_file")"
    local auth=""
    if [[ -n "$HF_TOKEN" && "$url" =~ huggingface\.co ]]; then
        auth="--header=\"Authorization: Bearer $HF_TOKEN\""
    fi
    
    if eval wget -nc --content-disposition --show-progress -e dotbytes=4M $auth -O "$target_file" "$url" 2>/dev/null; then
        echo "✅ Success: $(basename "$target_file")"
        return 0
    else
        echo " [!] FAILED: $(basename "$target_file")"
        return 1
    fi
}

install_hf_tools() {
    echo ""
    echo "🔧 Installing HuggingFace Tools..."
    echo "=================================="
    
    # Устанавливаем все HF инструменты
    pip install --no-cache-dir \
        huggingface-hub \
        huggingface \
        2>/dev/null || true
    
    # Настраиваем кэш в workspace (сохраняется между перезапусками)
    export HF_HOME="${HF_CACHE_DIR}"
    mkdir -p "${HF_CACHE_DIR}"
    
    # Создаём конфиг с токеном
    if [[ -n "$HF_TOKEN" ]]; then
        mkdir -p "${HF_CACHE_DIR}/huggingface"
        echo "token: ${HF_TOKEN}" > "${HF_CACHE_DIR}/huggingface/token"
        chmod 600 "${HF_CACHE_DIR}/huggingface/token"
        echo "✅ HuggingFace token configured"
    fi
    
    # Проверяем установку
    echo ""
    echo "📦 Installed tools:"
    huggingface-cli --version 2>/dev/null && echo "   • huggingface-cli ✓"
    hf --version 2>/dev/null && echo "   • hf (new CLI) ✓"
    
    # Создаём удобные алиасы в .bashrc
    cat >> ~/.bashrc << 'EOF'

# HuggingFace shortcuts
alias hf-download='huggingface-cli download'
alias hf-upload='huggingface-cli upload'
alias hf-repo='huggingface-cli repo create'
alias hf-cache='huggingface-cli scan-cache'
alias hf-auth='huggingface-cli auth login'

# Quick model download
alias hf-dl='huggingface-cli download --local-dir-use-symlinks False'

# Show HF cache
alias hf-ls='du -sh ~/.cache/huggingface/hub 2>/dev/null || echo "Cache empty"'
EOF
    
    source ~/.bashrc
    echo ""
    echo "✅ HuggingFace tools installed and configured!"
    echo "   Cache directory: ${HF_CACHE_DIR}"
    echo "   Available commands: hf-download, hf-upload, hf-cache, hf-ls"
}

install_extra_pip() {
    echo "→ Installing Python dependencies..."
    pip install --no-cache-dir \
        transformers \
        accelerate \
        sentencepiece \
        huggingface-hub \
        einops \
        safetensors \
        opencv-python \
        imageio \
        diffusers \
        2>/dev/null || true
}

# === MAIN ===
echo "🔧 Setting up environment..."
clone_comfyui_if_needed
install_extra_pip
install_nodes
install_hf_tools

echo ""
echo "📦 DOWNLOADING MODELS..."
echo "========================"

# 1. FLUX.2-klein-9B
echo "📦 FLUX.2-klein-9B..."
download_with_auth "${DIFFUSION_DIR}/flux-2-klein-9b.safetensors" "$FLUX_URL" || \
    echo "⚠️ FLUX.2 download failed"

# 2. Qwen3-8B Text Encoder (для FLUX.2)
echo ""
echo "📦 Qwen3-8B Text Encoder (FLUX.2)..."
download_with_auth "${TEXT_ENCODERS_DIR}/qwen_3_8b_fp8mixed.safetensors" "$QWEN_FP8_URL" || \
    download_with_auth "${TEXT_ENCODERS_DIR}/qwen_3_8b.safetensors" "$QWEN_FULL_URL" || \
    echo " [!] Qwen encoder download failed"

# 3. FLUX.2 VAE
echo ""
echo "📦 FLUX.2 VAE..."
download_with_auth "${VAE_DIR}/flux2-vae.safetensors" "$VAE_URL" || \
    echo " [!] VAE download failed"

# 4. Qwen GGUF (optional)
if [[ -n "$HF_TOKEN" ]]; then
    echo ""
    echo "📦 Qwen3-8B GGUF (optional)..."
    mkdir -p "${LLM_DIR}/Qwen3-8B-heretic-GGUF"
    download_with_auth "${LLM_DIR}/Qwen3-8B-heretic-GGUF/Qwen3-8B-heretic.Q8_0.gguf" "$QWEN_GGUF_URL" || true
fi

# 5. Z-IMAGE TURBO (BF16)
echo ""
echo "📦 Z-Image Turbo (BF16)..."
echo "   Model: z_image_turbo_bf16.safetensors (~24GB)"
download_with_auth "${DIFFUSION_DIR}/z_image_turbo_bf16.safetensors" "$ZIMAGE_MODEL_URL" || \
    echo " [!] Z-Image model download failed"

# 6. Z-Image Text Encoder
echo ""
echo "📦 Z-Image Text Encoder..."
echo "   Encoder: qwen_3_4b_fp8_mixed.safetensors"
download_with_auth "${TEXT_ENCODERS_DIR}/qwen_3_4b_fp8_mixed.safetensors" "$ZIMAGE_ENCODER_URL" || \
    echo " [!] Z-Image encoder download failed"

# 7. Z-Image VAE
echo ""
echo "📦 Z-Image VAE..."
echo "   VAE: ae.safetensors"
download_with_auth "${VAE_DIR}/ae.safetensors" "$ZIMAGE_VAE_URL" || \
    echo " [!] Z-Image VAE download failed"

# 8. Z-Image LoRA (optional)
echo ""
echo "📦 Z-Image LoRA (optional)..."
download_with_auth "${LORAS_DIR}/z_image_turbo_distill_patch_lora_bf16.safetensors" "$ZIMAGE_LORA_URL" || \
    echo " [!] Z-Image LoRA download failed"

echo ""
echo "✅ PROVISIONING COMPLETE!"
echo "========================="
echo ""
echo "📁 Model paths:"
echo ""
echo "   • Diffusion Models: ${DIFFUSION_DIR}/"
ls -lh "${DIFFUSION_DIR}"/*.safetensors 2>/dev/null || echo "      [NO MODELS]"
echo ""
echo "   • Text Encoders: ${TEXT_ENCODERS_DIR}/"
ls -lh "${TEXT_ENCODERS_DIR}"/*.safetensors 2>/dev/null || echo "      [NO MODELS]"
echo ""
echo "   • VAE: ${VAE_DIR}/"
ls -lh "${VAE_DIR}"/*.safetensors 2>/dev/null || echo "      [NO MODELS]"
echo ""
echo "   • LoRAs: ${LORAS_DIR}/"
ls -lh "${LORAS_DIR}"/*.safetensors 2>/dev/null || echo "      [NO LORAS]"
echo ""
echo "🔧 HuggingFace Tools:"
echo "   • Cache: ${HF_CACHE_DIR}"
du -sh "${HF_CACHE_DIR}" 2>/dev/null || echo "   • Size: checking..."
echo ""
echo "📚 Useful commands:"
echo "   • hf-download <repo>          - Download model"
echo "   • hf-ls                       - Show cache size"
echo "   • hf-cache                    - Scan cache"
echo "   • huggingface-cli whoami      - Check login"
echo ""
echo "🚀 ComfyUI will start on port 18188"
echo ""
