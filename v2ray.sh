#!/bin/bash
# Author: Jrohy
# github: https://github.com/Jrohy/multi-v2ray

# 记录最开始运行脚本的路径
begin_path="$(pwd)"

# 安装方式, 0为全新安装, 1为保留v2ray配置更新
install_way=0

# 定义操作变量, 0为否, 1为是
help=0
remove=0
chinese=0

# Keep installer and Python sources together, including when used from a checkout.
source_repo="${MULTI_V2RAY_REPOSITORY:-brian952700/multi-v2ray}"
source_ref="${MULTI_V2RAY_REF:-master}"
base_source_path="https://raw.githubusercontent.com/${source_repo}/${source_ref}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
manager_home="/opt/multi-v2ray"
venv_path="$manager_home/venv"
source_dir=""
source_tmp=""
is_debian=0

prepare_source() {
    if [[ -f "$script_dir/setup.py" && -d "$script_dir/v2ray_util" ]]; then
        source_dir="$script_dir"
    else
        source_tmp="$(mktemp -d)" || return 1
        if ! curl -fLsS --retry 3 "https://api.github.com/repos/${source_repo}/tarball/${source_ref}" -o "$source_tmp/source.tar.gz"; then
            rm -rf -- "$source_tmp"
            return 1
        fi
        mkdir "$source_tmp/source" || return 1
        tar -xzf "$source_tmp/source.tar.gz" --strip-components=1 -C "$source_tmp/source" || return 1
        source_dir="$source_tmp/source"
    fi
    [[ -f "$source_dir/setup.py" && -f "$source_dir/go.sh" ]]
}

core_script() {
    if [[ -n "$source_dir" ]]; then
        bash "$source_dir/go.sh" "$@"
    elif [[ -f "$manager_home/go.sh" ]]; then
        bash "$manager_home/go.sh" "$@"
    else
        local core_tmp
        core_tmp="$(mktemp)" || return 1
        curl -fLsS --retry 3 "$base_source_path/go.sh" -o "$core_tmp" || { rm -f "$core_tmp"; return 1; }
        bash "$core_tmp" "$@"
        local result=$?
        rm -f "$core_tmp"
        return "$result"
    fi
}

util_path="/etc/v2ray_util/util.cfg"
util_cfg="$base_source_path/v2ray_util/util_core/util.cfg"
bash_completion_shell="$base_source_path/v2ray"
clean_iptables_shell="$base_source_path/v2ray_util/global_setting/clean_iptables.sh"

# Centos 临时取消别名
[[ -f /etc/redhat-release && -z "$(echo "$SHELL" | grep zsh)" ]] && unalias -a

[[ -z "$(echo "$SHELL" | grep zsh)" ]] && env_file=".bashrc" || env_file=".zshrc"

####### color code ########
red="31m"
green="32m"
yellow="33m"
blue="36m"
fuchsia="35m"

colorEcho() {
    color=$1
    echo -e "\033[${color}${@:2}\033[0m"
}

get_pip_cmd() {
    if [[ -x "$venv_path/bin/pip" ]]; then
        echo "$venv_path/bin/pip"
        return 0
    elif command -v pip >/dev/null 2>&1; then
        echo "pip"
        return 0
    elif command -v pip3 >/dev/null 2>&1; then
        echo "pip3"
        return 0
    elif command -v python3 >/dev/null 2>&1; then
        echo "python3 -m pip"
        return 0
    fi
    return 1
}

find_v2ray_util_bin() {
    local bin_path

    bin_path="$(command -v v2ray-util 2>/dev/null)"
    if [[ -n "$bin_path" && -x "$bin_path" ]]; then
        echo "$bin_path"
        return 0
    fi

    for bin_path in \
        "$venv_path/bin/v2ray-util" \
        /usr/local/bin/v2ray-util \
        /usr/bin/v2ray-util \
        /root/.local/bin/v2ray-util
    do
        if [[ -x "$bin_path" ]]; then
            echo "$bin_path"
            return 0
        fi
    done

    return 1
}

####### get params #########
while [[ $# > 0 ]]; do
    key="$1"
    case $key in
        --remove)
            remove=1
            ;;
        -h|--help)
            help=1
            ;;
        -k|--keep)
            install_way=1
            colorEcho "${blue}" "keep config to update\n"
            ;;
        --zh)
            chinese=1
            colorEcho "${blue}" "安装中文版..\n"
            ;;
        *)
            # unknown option
            ;;
    esac
    shift
done
#############################

help() {
    echo "bash v2ray.sh [-h|--help] [-k|--keep] [--remove]"
    echo "  -h, --help           Show help"
    echo "  -k, --keep           keep the config.json to update"
    echo "      --remove         remove v2ray,xray && multi-v2ray"
    echo "                       no params to new install"
    return 0
}

removeV2Ray() {
    local pip_cmd rc_service rc_file

    # 卸载V2ray脚本
    core_script --remove || return 1
    rm -rf /etc/v2ray >/dev/null 2>&1
    rm -rf /var/log/v2ray >/dev/null 2>&1

    # 卸载Xray脚本
    core_script --remove -x || return 1
    rm -rf /etc/xray >/dev/null 2>&1
    rm -rf /var/log/xray >/dev/null 2>&1

    # 清理v2ray相关iptable规则
    if [[ -f "$manager_home/clean_iptables.sh" ]]; then
        bash "$manager_home/clean_iptables.sh"
    fi
    systemctl disable --now multi-v2ray-iptables.service >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/multi-v2ray-iptables.service
    systemctl daemon-reload >/dev/null 2>&1 || true

    # 卸载multi-v2ray
    pip_cmd="$(get_pip_cmd 2>/dev/null)"
    if [[ -n "$pip_cmd" ]]; then
        $pip_cmd uninstall v2ray_util -y >/dev/null 2>&1
    fi

    rm -rf /usr/share/bash-completion/completions/v2ray.bash >/dev/null 2>&1
    rm -rf /usr/share/bash-completion/completions/v2ray >/dev/null 2>&1
    rm -rf /usr/share/bash-completion/completions/xray >/dev/null 2>&1
    rm -rf /etc/bash_completion.d/v2ray.bash >/dev/null 2>&1
    rm -rf /usr/local/bin/v2ray >/dev/null 2>&1
    rm -rf /usr/local/bin/xray >/dev/null 2>&1
    rm -rf /usr/local/bin/v2ray-util >/dev/null 2>&1
    rm -rf /root/.local/bin/v2ray-util >/dev/null 2>&1
    rm -rf /etc/v2ray_util >/dev/null 2>&1
    rm -rf /etc/profile.d/iptables.sh >/dev/null 2>&1
    rm -rf /root/.iptables >/dev/null 2>&1
    rm -f /root/.ip6tables
    rm -rf /opt/multi-v2ray

    # 删除v2ray定时更新任务
    crontab -l 2>/dev/null | sed '/SHELL=/d;/v2ray/d;/xray/d' > crontab.txt
    crontab crontab.txt >/dev/null 2>&1
    rm -f crontab.txt >/dev/null 2>&1

    if [[ ${package_manager} == 'dnf' || ${package_manager} == 'yum' ]]; then
        systemctl restart crond >/dev/null 2>&1
    else
        systemctl restart cron >/dev/null 2>&1
    fi

    # 删除multi-v2ray环境变量
    sed -i '/v2ray/d' ~/"$env_file" 2>/dev/null
    sed -i '/xray/d' ~/"$env_file" 2>/dev/null
    source ~/"$env_file" >/dev/null 2>&1

    rc_service="$(systemctl status rc-local 2>/dev/null | grep loaded | egrep -o "[A-Za-z/._-]+/rc-local.service" | head -n1)"
    if [[ -n "$rc_service" && -f "$rc_service" ]]; then
        rc_file="$(grep ExecStart "$rc_service" | awk '{print $1}' | cut -d = -f2)"
        [[ -n "$rc_file" && -f "$rc_file" ]] && sed -i '/iptables/d' "$rc_file"
    fi

    colorEcho "${green}" "uninstall success!"
}

closeSELinux() {
    # 禁用SELinux
    if [[ -s /etc/selinux/config ]] && grep -q 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        setenforce 0 >/dev/null 2>&1
    fi
}

checkSys() {
    # 检查是否为Root
    [[ "$(id -u)" != "0" ]] && { colorEcho "${red}" "Error: You must be root to run this script"; exit 1; }

    if [[ -r /etc/os-release ]]; then
        local ID="" ID_LIKE=""
        . /etc/os-release
        [[ "$ID" == debian || "$ID_LIKE" == *debian* ]] && is_debian=1
    fi

    if command -v apt-get >/dev/null 2>&1; then
        package_manager='apt-get'
    elif command -v dnf >/dev/null 2>&1; then
        package_manager='dnf'
    elif command -v yum >/dev/null 2>&1; then
        package_manager='yum'
    else
        colorEcho "${red}" "Not support OS!"
        exit 1
    fi
}

# 安装依赖
installDependent() {
    if [[ ${package_manager} == 'dnf' || ${package_manager} == 'yum' ]]; then
        ${package_manager} install socat crontabs bash-completion which -y
    else
        ${package_manager} update -y || return 1
        local ntp_package=ntpdate
        if apt-cache show ntpsec-ntpdate >/dev/null 2>&1; then
            ntp_package=ntpsec-ntpdate
        fi
        ${package_manager} install socat cron bash-completion "$ntp_package" gawk curl ca-certificates iptables procps unzip tar -y || return 1
    fi

    # install python3 & pip
    if [[ $is_debian == 1 ]]; then
        apt-get install -y python3 python3-venv || return 1
        mkdir -p "$manager_home" || return 1
        python3 -m venv "$venv_path" || return 1
    else
        source <(curl -fsSL https://python3.netlify.app/install.sh)
    fi
}

updateProject() {
    local pip_cmd rc_service rc_file local_ip iptable_way v2ray_util_bin pip_install_ok=0

    pip_cmd="$(get_pip_cmd)"
    [[ -z "$pip_cmd" ]] && colorEcho "${red}" "pip no install!" && exit 1

    [[ -e /etc/profile.d/iptables.sh ]] && rm -f /etc/profile.d/iptables.sh

    rc_service="$(systemctl status rc-local 2>/dev/null | grep loaded | egrep -o "[A-Za-z/._-]+/rc-local.service" | head -n1)"
    rc_file=""
    [[ -n "$rc_service" && -f "$rc_service" ]] && rc_file="$(grep ExecStart "$rc_service" | awk '{print $1}' | cut -d = -f2)"

    if [[ $is_debian != 1 && -n "$rc_file" ]]; then
        if [[ ! -e "$rc_file" || -z "$(grep iptables "$rc_file" 2>/dev/null)" ]]; then
            local_ip="$(curl -s http://api.ipify.org 2>/dev/null)"
            [[ "$(echo "$local_ip" | grep :)" ]] && iptable_way="ip6tables" || iptable_way="iptables"

            if [[ ! -e "$rc_file" || -z "$(grep "/bin/bash" "$rc_file" 2>/dev/null)" ]]; then
                echo "#!/bin/bash" >> "$rc_file"
            fi

            if [[ -z "$(grep "\[Install\]" "$rc_service" 2>/dev/null)" ]]; then
                cat >> "$rc_service" << EOF

[Install]
WantedBy=multi-user.target
EOF
                systemctl daemon-reload
            fi

            echo "[[ -e /root/.iptables ]] && ${iptable_way}-restore -c < /root/.iptables" >> "$rc_file"
            chmod +x "$rc_file"
            systemctl restart rc-local >/dev/null 2>&1
            systemctl enable rc-local >/dev/null 2>&1

            ${iptable_way}-save -c > /root/.iptables 2>/dev/null
        fi
    fi

    # Install this source revision into the dedicated Debian environment.
    $pip_cmd install --upgrade "$source_dir" || return 1
    local manager_python
    if [[ $is_debian == 1 ]]; then
        manager_python="$venv_path/bin/python3"
    else
        manager_python="$(dirname "$(find_v2ray_util_bin)")/python3"
    fi
    [[ -x "$manager_python" ]] || manager_python=python3
    # Existing configuration remains in place during --keep.
    "$manager_python" -c 'import v2ray_util.main' || return 1
    mkdir -p "$manager_home" || return 1
    cp "$source_dir/go.sh" "$manager_home/go.sh" || return 1
    cp "$source_dir/v2ray_util/global_setting/clean_iptables.sh" "$manager_home/clean_iptables.sh" || return 1
    if [[ $is_debian == 1 ]]; then
        cp "$source_dir/v2ray_util/global_setting/restore_iptables.sh" "$manager_home/restore_iptables.sh" || return 1
        if [[ -f /root/.iptables ]] && grep -q 'Generated by ip6tables-save' /root/.iptables; then
            mv /root/.iptables /root/.ip6tables || return 1
        fi
        # Debian no longer guarantees an enabled rc-local service. Do not edit
        # the distribution's unit or mix the two address families in one file.
        if [[ -d /run/systemd/system ]]; then
            cp "$source_dir/multi-v2ray-iptables.service" /etc/systemd/system/ || return 1
            systemctl daemon-reload || return 1
            systemctl enable multi-v2ray-iptables.service || return 1
            systemctl enable --now cron || return 1
        fi
    fi

    if [[ -e "$util_path" ]]; then
        [[ -z "$(grep lang "$util_path" 2>/dev/null)" ]] && echo "lang=en" >> "$util_path"
    else
        mkdir -p /etc/v2ray_util
        cp "$source_dir/v2ray_util/util_core/util.cfg" "$util_path" || return 1
    fi

    [[ $chinese == 1 ]] && sed -i "s/lang=en/lang=zh/g" "$util_path"

    if [[ $is_debian == 1 ]]; then
        v2ray_util_bin="$venv_path/bin/v2ray-util"
    else
        v2ray_util_bin="$(find_v2ray_util_bin)"
    fi
    [[ -z "$v2ray_util_bin" ]] && colorEcho "${red}" "v2ray-util command not found after install!" && exit 1

    rm -f /usr/local/bin/v2ray >/dev/null 2>&1
    ln -sf "$v2ray_util_bin" /usr/local/bin/v2ray
    rm -f /usr/local/bin/xray >/dev/null 2>&1
    ln -sf "$v2ray_util_bin" /usr/local/bin/xray

    hash -r

    [[ ! -x /usr/local/bin/v2ray ]] && colorEcho "${red}" "create /usr/local/bin/v2ray failed!" && exit 1
    [[ ! -x /usr/local/bin/xray ]] && colorEcho "${red}" "create /usr/local/bin/xray failed!" && exit 1

    # 移除旧的v2ray bash_completion脚本
    [[ -e /etc/bash_completion.d/v2ray.bash ]] && rm -f /etc/bash_completion.d/v2ray.bash
    [[ -e /usr/share/bash-completion/completions/v2ray.bash ]] && rm -f /usr/share/bash-completion/completions/v2ray.bash

    # 更新v2ray bash_completion脚本
    cp "$source_dir/v2ray" /usr/share/bash-completion/completions/v2ray || return 1
    cp "$source_dir/v2ray" /usr/share/bash-completion/completions/xray || return 1

    if [[ -z "$(echo "$SHELL" | grep zsh)" ]]; then
        source /usr/share/bash-completion/completions/v2ray >/dev/null 2>&1
        source /usr/share/bash-completion/completions/xray >/dev/null 2>&1
    fi

    # 安装V2ray主程序
    if [[ ${install_way} == 0 ]]; then
        core_script || return 1
    fi
    return 0
}

# 时间同步
timeSync() {
    if [[ ${install_way} == 0 ]]; then
        echo -e "Time Synchronizing.. "
        if command -v ntpdate >/dev/null 2>&1; then
            ntpdate pool.ntp.org
        elif command -v chronyc >/dev/null 2>&1; then
            chronyc -a makestep
        fi

        if [[ $? -eq 0 ]]; then
            colorEcho "${green}" "Time Sync Success"
            colorEcho "${blue}" "now: $(date -R)"
        fi
    fi
}

profileInit() {
    # 清理v2ray模块环境变量
    [[ -f ~/"$env_file" && -n "$(grep v2ray ~/"$env_file" 2>/dev/null)" ]] && sed -i '/v2ray/d' ~/"$env_file" && source ~/"$env_file" >/dev/null 2>&1

    # 解决Python3中文显示问题
    [[ -f ~/"$env_file" && -z "$(grep PYTHONIOENCODING=utf-8 ~/"$env_file" 2>/dev/null)" ]] && echo "export PYTHONIOENCODING=utf-8" >> ~/"$env_file" && source ~/"$env_file" >/dev/null 2>&1

    # 全新安装的新配置
    if [[ ${install_way} == 0 ]]; then
        v2ray new || return 1
    fi

    echo ""
}

installFinish() {
    # 回到原点
    cd "${begin_path}"

    [[ ${install_way} == 0 ]] && WAY="install" || WAY="update"
    colorEcho "${green}" "multi-v2ray ${WAY} success!\n"

    if [[ ${install_way} == 0 ]]; then
        clear
        hash -r
        v2ray info
        echo -e "please input 'v2ray' command to manage v2ray\n"
    fi
}

main() {
    [[ ${help} == 1 ]] && help && return
    checkSys
    [[ ${remove} == 1 ]] && { removeV2Ray; return $?; }

    [[ ${install_way} == 0 ]] && colorEcho "${blue}" "new install\n"

    installDependent || return 1
    prepare_source || return 1
    closeSELinux
    timeSync
    updateProject || { [[ -n "$source_tmp" ]] && rm -rf -- "$source_tmp"; return 1; }
    profileInit || return 1
    [[ -n "$source_tmp" ]] && rm -rf -- "$source_tmp"
    installFinish
}

main
