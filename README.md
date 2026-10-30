# Claude 汉化

把 Claude 桌面版的界面一键换成中文，Mac 和 Windows 各一份。

实际的汉化工作由开源项目 [javaht/claude-desktop-zh-cn](https://github.com/javaht/claude-desktop-zh-cn)（MIT 协议）完成，这里的脚本只负责检查环境、调用补丁、备份和恢复，让不熟悉命令行的人也能双击完成。

## 下载

点本页右上方绿色的 **Code → Download ZIP**，解压后进入对应系统的文件夹。

## Mac：`Claude一键汉化-mac`

1. 先保存 Claude 里正在进行的工作，安装时会自动退出 Claude。
2. 双击 `Claude一键汉化.command`，按回车开始，然后输入这台 Mac 的开机密码。
3. 等 2～3 分钟，Claude 会以中文重新打开。

- 脚本每次运行时都会从 GitHub 下载 javaht 补丁的最新版，国内网络可能需要开代理。
- 已经汉化过的 Mac 再次运行，可以选“重新安装”或“恢复英文原版”。
- 双击打不开、提示无法验证开发者等问题，见文件夹里的 `使用说明.txt`。

## Windows：`Claude一键汉化-win`

1. 先安装 Claude 桌面版，并至少打开一次。
2. 复制整个文件夹（不要只复制 bat 文件），双击 `一键安装中文.bat`，在管理员授权弹窗里点“是”。
3. Claude 会被关闭，装完后自动以中文重新打开。

- 恢复原版：双击 `一键卸载中文.bat`。
- `payload` 文件夹是 javaht/claude-desktop-zh-cn 1.4.19 版的原样副本，不需要联网下载。

## 注意

- Claude 自动更新后会变回英文，再运行一次脚本即可。
- 汉化会让 Claude 的官方签名失效，这是补丁的正常结果；恢复原版后会回到官方签名。
- 用官方账号登录后，部分由网页提供的内容（如账号设置页）可能仍是英文。
- 本项目与 Anthropic 官方无关。
