# 🤝 如何参与贡献 (Contributing Guide)

感谢你对 Xray-Auto 项目感兴趣！我们非常欢迎任何形式的贡献，包括提交 Bug、改进文档或开发新功能。

## 🛠️ 开发流程 (Workflow)

1.  **Fork 本仓库**：点击右上角的 `Fork` 按钮，将项目复制到你自己的账号下。
2.  **克隆代码**：
    ```bash
    git clone [https://github.com/你的用户名/Xray-Auto.git](https://github.com/你的用户名/Xray-Auto.git)
    cd Xray-Auto
    ```
3.  **创建分支**：不要直接在 `main` 分支修改，请为你的功能创建一个新分支。
    ```bash
    git checkout -b feat/new-function  # 开发新功能
    # 或者
    git checkout -b fix/bug-fix       # 修复 Bug
    ```
4.  **修改代码**：进行你的修改。
    * 请遵循现有的代码风格（Shell 脚本规范）。
    * 修改核心逻辑时，请确保 `core/` 模块的函数封装正确。
    * 如果是新增工具，请放入 `tools/` 目录。
5.  **提交更改**：
    ```bash
    git add .
    git commit -m "Feat: 增加了一键卸载功能"  # 请使用清晰的 Commit 信息
    git push origin feat/new-function
    ```
6.  **提交 PR (Pull Request)**：回到 GitHub 页面，系统会提示你提交 Pull Request。请填写清晰的描述，说明你改了什么。

## 📋 代码规范 (Code Style)

* **脚本头**：所有新脚本必须包含 `#!/bin/bash` 和必要的颜色变量定义。
* **注释**：关键逻辑请添加注释（推荐中文）。
* **模块化**：请勿将大段逻辑直接写入 `install.sh`，应尽量封装在 `core/` 下的模块中。

## 🧪 测试 (Testing)

在提交 PR 之前，请务必在测试机（如虚拟机或闲置 VPS）上运行一遍安装流程，确保：
1.  `bootstrap.sh` 能正常拉取并启动安装。
2.  安装后 `xray` 服务能正常启动。
3.  `info` 和 `net` 等命令能正常工作。

感谢你的贡献！🚀
