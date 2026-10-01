# 1.6.2 发布记录

2026-10-01，用户明确授权直接发布 GitHub，并要求不重新测试。

发布目标：`ym911x/Minget`、`main`、新增 annotated tag `v1.6.2`、公开 Latest Release。
沿用本轮已有测试、签名和真实界面证据，不重跑测试或构建；发布提交使用 `[skip ci]` 跳过自动 CI，不宣称本轮远端 CI 通过。
仅发布源码，不上传本地签名 App。示例 PNG 为生产组件测试渲染，部分 Logo 使用测试资源回退，不作为正式运行截图附件。
新版本证据中的本机路径以 `$HOME` / `$PROJECT_ROOT` 脱敏，原测试结果不变，manifest 按脱敏文件重新计算。

## 完成与核验

- 公开发布时间：2026-10-01 17:38:11 Asia/Shanghai。
- Release：[v1.6.2](https://github.com/ym911x/Minget/releases/tag/v1.6.2)，Latest、非草稿、非预发布；公开页面 HTTP 200。
- 发布代码提交：`a8a9526c9d48065b5f7b31dce40c9d724c542c0d`。
- Annotated tag 对象：`cb420a9d52eab6f1643c2ad44eb1cf1cd2baefa7`，解引用到上述发布代码提交；远端引用已核对。
- main 已从 `91f5ee4` 快进到发布代码；本次发布台账作为后续文档提交同步，版本标签保持不变。
- GitHub Release 自定义附件为空，维持源码分发。
- 发布代码提交的 Actions 列表为空，符合用户不重跑测试及 `[skip ci]` 设置。没有宣称远端 CI 通过。
- 本机正式 App 已为1.6.2；此次仅发布和同步文档，未重新测试、构建或替换安装包。

