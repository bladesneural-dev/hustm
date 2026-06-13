#!/bin/bash
set -e
source /venv/main/bin/activate 2>/dev/null || true

WORKSPACE=${WORKSPACE:-/workspace}
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

echo "=== FLUX.2-klein-9B + Qwen3-8B + Z-Image Turbo + ComfyUI 0.21.0 ==="

# === CUSTOM NODES (GitHub) ===
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
CHECKPOINTS_DIR="${COMFYUI_DIR}/models/checkpoints"
ZIMAGE_DIR="${COMFYUI_DIR}/models/Z-Image-Turbo"

# === MODEL URLS ===
# FLUX.2
FLUX_URL="https://huggingface.co/black-forest-labs/FLUX.2-klein-9B/resolve/main/flux-2-klein-9b.safetensors"

# Qwen Encoders
QWEN_FP8_URL="https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors"
QWEN_FULL_URL="https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/qwen_3_8b.safetensors"

# VAE
VAE_URL="https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors"

# Qwen GGUF (optional)
QWEN_GGUF_URL="https://huggingface.co/mradermacher/Qwen3-8B-heretic-GGUF/resolve/main/Qwen3-8B-heretic.Q8_0.gguf"

# Z-Image Turbo (HuggingFace)
ZIMAGE_MODEL_URL="https://huggingface.co/Tongyi-MAI/Z-Image-Turbo/resolve/main/z-image-turbo.safetensors"
ZIMAGE_REPO="Tongyi-MAI/Z-Image-Turbo"

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
        if [[ "$url" =~ huggingface\.co ]]; then
            echo "     Reason: 403 Forbidden - Check HF_TOKEN permissions"
            echo "     Action: Accept license at $(echo $url | cut -d'/resolve' -f1)"
        fi
        return 1
    fi
}

download_zimage_turbo() {
    echo ""
    echo "📦 Z-Image Turbo Setup..."
    echo "========================"
    
    mkdir -p "${ZIMAGE_DIR}"
    
    # Скачиваем основную модель
    local model_file="${ZIMAGE_DIR}/z-image-turbo.safetensors"
    if [[ -f "$model_file" ]]; then
        echo "✅ Z-Image Turbo model exists"
    else
        echo "→ Downloading Z-Image Turbo model..."
        local auth=""
        if [[ -n "$HF_TOKEN" ]]; then
            auth="--header=\"Authorization: Bearer $HF_TOKEN\""
        fi
        
        if eval wget -nc --show-progress -e dotbytes=4M $auth -O "$model_file" \
            "https://huggingface.co/${ZIMAGE_REPO}/resolve/main/z-image-turbo.safetensors" 2>/dev/null; then
            echo "✅ Z-Image Turbo downloaded"
        else
            echo " [!] Z-Image Turbo download failed"
            echo "     Try: Accept license at https://huggingface.co/${ZIMAGE_REPO}"
        fi
    fi
    
    # Клонируем ComfyUI ноды для Z-Image если есть
    echo "→ Checking for Z-Image ComfyUI nodes..."
    local nodes_dir="${COMFYUI_DIR}/custom_nodes"
    
    # Ищем официальные ноды Tongyi
    if [[ ! -d "${nodes_dir}/ComfyUI-Z-Image" ]]; then
        echo "→ Cloning ComfyUI-Z-Image nodes..."
        cd "${nodes_dir}"
        # Пробуем найти репозиторий с нодами
        if ! git clone https://github.com/Tongyi-MAI/ComfyUI-Z-Image.git 2>/dev/null; then
            echo " [!] ComfyUI-Z-Image nodes not found, trying alternative..."
            # Альтернативный репозиторий если есть
        fi
    fi
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

echo ""
echo "📦 DOWNLOADING MODELS..."
echo "========================"

# 1. FLUX.2-klein-9B (GATED - требует токена с доступом)
download_with_auth "${DIFFUSION_DIR}/flux-2-klein-9b.safetensors" "$FLUX_URL" || \
    echo "⚠️ FLUX.2 download failed - check token permissions"

# 2. Qwen3-8B Text Encoder (FP8 preferred)
echo ""
echo "📦 Qwen3-8B Text Encoder..."
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

# 5. Z-Image Turbo
download_zimage_turbo

echo ""
echo "✅ PROVISIONING COMPLETE!"
echo "========================="
echo ""
echo "📁 Model paths:"
echo "   • Diffusion: ${DIFFUSION_DIR}/"
ls -lh "${DIFFUSION_DIR}"/*.safetensors 2>/dev/null || echo "      [NO MODELS]"
echo ""
echo "   • Text Encoders: ${TEXT_ENCODERS_DIR}/"
ls -lh "${TEXT_ENCODERS_DIR}"/*.safetensors 2>/dev/null || echo "      [NO MODELS]"
echo ""
echo "   • VAE: ${VAE_DIR}/"
ls -lh "${VAE_DIR}"/*.safetensors 2>/dev/null || echo "      [NO MODELS]"
echo ""
echo "   • Z-Image Turbo: ${ZIMAGE_DIR}/"
ls -lh "${ZIMAGE_DIR}"/*.safetensors 2>/dev/null || echo "      [NO MODELS]"
echo ""
echo "🚀 ComfyUI will start on port 18188"
echo ""
