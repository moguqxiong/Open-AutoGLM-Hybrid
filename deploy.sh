#!/data/data/com.termux/files/usr/bin/bash

# Open-AutoGLM 混合方案 - Termux 一键部署脚本
# 版本: 2.0.0 (基于实战避坑优化版)

set -e  # 遇到错误立即停止

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- 辅助函数 ---
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_header() {
    echo ""
    echo "============================================================"
    echo "  Open-AutoGLM 一键部署 (v2.0 避坑版)"
    echo "  已针对 Termux 环境进行 Rust、Pillow 及网络源优化"
    echo "============================================================"
    echo ""
}

# 1. 环境准备与系统库安装
prepare_environment() {
    print_info "步骤 1/6: 更新系统并安装底层依赖..."
    
    # 更新源
    pkg update -y
    
    # 安装基础工具
    pkg install git curl wget nano -y
    
    # [关键修复] 安装 Rust 编译器 (用于编译 jiter, pydantic-core)
    print_info "安装 Rust 编译环境 (可能需要一点时间)..."
    pkg install rust binutils -y
    
    # [关键修复] 直接安装 Termux 适配版 Pillow (避免手动编译缺库)
    print_info "安装 Python 及 Pillow 预编译包..."
    pkg install python python-pillow -y
    
    # 验证安装
    if command -v rustc &> /dev/null; then
        print_success "环境依赖安装完毕 (Python: $(python --version), Rust: $(rustc --version))"
    else
        print_error "Rust 安装失败，脚本退出"
        exit 1
    fi
}

# 2. 配置国内加速源 (解决网络卡顿)
configure_mirrors() {
    print_info "步骤 2/6: 配置国内镜像源..."

    # 配置 Pip 清华源
    pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
    
    # [关键修复] 配置 Cargo 清华源 (使用 sparse+https 协议且修正 URL 结尾斜杠)
    print_info "配置 Cargo (Rust) 加速源..."
    mkdir -p ~/.cargo
    
    # 删除旧配置防止冲突
    rm -f ~/.cargo/config
    rm -f ~/.cargo/config.toml
    
    cat > ~/.cargo/config.toml << EOF
[source.crates-io]
replace-with = 'tuna'

[source.tuna]
registry = "sparse+https://mirrors.tuna.tsinghua.edu.cn/crates.io-index/"
EOF
    
    # 设置 Git CLI 环境变量以防 libgit2 报错
    export CARGO_NET_GIT_FETCH_WITH_CLI=true
    
    print_success "镜像源配置完成"
}

# 3. 安装 Python 核心依赖
install_python_deps() {
    print_info "步骤 3/6: 安装 Python 核心依赖..."
    
    # 注意：Termux 中禁止 pip install --upgrade pip，已跳过
    
    # 预先安装构建工具
    print_info "安装构建工具 maturin..."
    pip install maturin
    
    # [高能预警] 编译 pydantic-core
    print_info "正在安装 pydantic-core 和 openai..."
    print_warning "⚠️ 注意：此步骤会在手机上进行编译，可能卡在 'Building wheel' 5-10分钟。"
    print_warning "⚠️ 请耐心等待，绝对不要强制退出！"
    
    pip install openai requests
    
    print_success "Python 依赖安装完成"
}

# 4. 下载项目代码
download_project() {
    print_info "步骤 4/6: 下载 Open-AutoGLM 项目..."
    
    cd ~
    if [ -d "Open-AutoGLM" ]; then
        print_warning "检测到 Open-AutoGLM 目录已存在，跳过 Clone"
    else
        git clone https://github.com/zai-org/Open-AutoGLM.git
    fi
    
    cd ~/Open-AutoGLM
    
    # 安装项目自身依赖 (去掉 pillow，因为已经用 pkg 装过了)
    # 使用 sed 临时从 requirements 中去掉 pillow 防止 pip 尝试重新编译
    if [ -f "requirements.txt" ]; then
        sed -i '/Pillow/d' requirements.txt
        sed -i '/pillow/d' requirements.txt
        pip install -r requirements.txt
    fi
    
    # 安装当前目录包
    pip install -e .
    
    print_success "项目代码下载与安装完成"
}

# 5. 下载混合方案脚本 (修正逻辑)
setup_hybrid_script() {
    print_info "步骤 5/6: 下载混合控制脚本..."
    
    mkdir -p ~/.autoglm
    
    # [关键修复] 只有下载失败才生成占位文件，而不是下载后覆盖
    TARGET_URL="https://raw.githubusercontent.com/moguqxiong/Open-AutoGLM-Hybrid/refs/heads/main/phone_controller.py"
    
    if wget -O ~/.autoglm/phone_controller.py "$TARGET_URL"; then
        print_success "phone_controller.py 下载成功"
    else
        print_warning "下载失败 (可能是网络原因)，生成本地测试占位文件..."
        cat > ~/.autoglm/phone_controller.py << 'PYTHON_EOF'
# 这是一个占位文件，因为脚本下载失败
print("警告: 这是一个占位文件，实际控制逻辑未加载。")
pass
PYTHON_EOF
    fi
}

# 6. 配置启动与 API
configure_launcher() {
    print_info "步骤 6/6: 配置启动项..."
    
    # 询问 API Key
    echo ""
    echo -e "${YELLOW}请输入您的 GRS AI API Key (如果暂时没有，直接回车):${NC}"
    read -r api_key
    
    if [ -z "$api_key" ]; then
        api_key="your_api_key_here"
    fi
    
    # 生成配置文件
    cat > ~/.autoglm/config.sh << EOF
#!/data/data/com.termux/files/usr/bin/bash
export PHONE_AGENT_BASE_URL="https://api.grsai.com/v1"
export PHONE_AGENT_API_KEY="$api_key"
export PHONE_AGENT_MODEL="gpt-4-vision-preview"
export AUTOGLM_HELPER_URL="http://localhost:8080"
EOF

    # 自动加载配置
    if ! grep -q "source ~/.autoglm/config.sh" ~/.bashrc; then
        echo "" >> ~/.bashrc
        echo "source ~/.autoglm/config.sh" >> ~/.bashrc
    fi
    
    # 创建启动命令
    mkdir -p ~/bin
    cat > ~/bin/autoglm << 'LAUNCHER_EOF'
#!/data/data/com.termux/files/usr/bin/bash
source ~/.autoglm/config.sh
# 确保使用 Cargo 的配置
export CARGO_NET_GIT_FETCH_WITH_CLI=true
cd ~/Open-AutoGLM
python -m phone_agent.cli
LAUNCHER_EOF
    
    chmod +x ~/bin/autoglm
    
    # 将 ~/bin 加入 PATH
    if ! grep -q 'export PATH=$PATH:~/bin' ~/.bashrc; then
        echo 'export PATH=$PATH:~/bin' >> ~/.bashrc
    fi

    # 立即生效环境变量
    export PATH=$PATH:~/bin
}

# --- 主程序 ---
main() {
    print_header
    prepare_environment
    configure_mirrors
    install_python_deps
    download_project
    setup_hybrid_script
    configure_launcher
    
    echo ""
    print_success "====== 部署全部完成 ======"
    echo "请执行以下操作："
    echo "1. 确保 AutoGLM Helper App 已在后台运行"
    echo "2. 重启 Termux 或输入 source ~/.bashrc"
    echo "3. 输入命令启动: autoglm"
}

main
