# 公开仓库功能复验

验证日期：2026-10-16（Asia/Shanghai）。

仓库：https://github.com/Gahao123/riscv-dev-env

提交：`c191c0388eddf621371e398657d29efc0b09960e`。

## 结论

该提交的第一阶段开发镜像功能复验通过。Ubuntu 24.04 使用原始 Dockerfile 完成完整禁用缓存构建；Ubuntu 26.04 使用原样的开发阶段及相同的已构建 GCC 产物完成构建。两套新镜像均通过普通用户、编译执行、预期失败返回和目录挂载检查。公开仓库源码没有修改。

本机 Docker 29.1.3 旧式构建器没有命中已生成的缓存，额外重跑 build.sh 时开始重复编译 GCC。两次重复尝试被主动中止，不计为构建脚本完整通过。后续采用明确的分阶段验证；不能把这次结果表述为“两个原始脚本均已从头完整运行通过”。

## 从公开仓库重新获取

- 无凭据请求 GitHub 元数据，确认仓库为 public；独立 clone 的提交为 c191c03。
- 使用该提交的 Git archive 在独立 WSL 目录展开，初始没有 `.cache`。
- 仓库下载脚本重新获取五份归档，全部校验通过；没有复制旧源码缓存或旧工具链安装目录。
- 两个锁定基础镜像实际执行 `docker pull --platform linux/amd64` 并成功解析。已有基础镜像层复用，没有重新下载所有层。

## 构建方法与边界

1. Ubuntu 24.04 使用公开原始 Dockerfile，通过 `docker build --no-cache` 完整重建 GCC/Newlib、Spike 和开发镜像。该日志没有 Docker 构建层缓存命中。
2. 原始 build.sh 的额外复跑遇到本机缓存未命中，因重复编译成本主动中止；日志完整保留，未当作产品编译失败或测试通过。
3. Ubuntu 26.04 验证时生成辅助 Dockerfile：把工具链构建阶段替换成已经完整构建成功的 `cc48e644a57b` 镜像引用，后面的 development 阶段与公开 Dockerfile 逐字一致，并对该运行阶段禁用缓存。
4. development 阶段摘要为 `ebc0391cd6d1d2eb97332017711028cacd45081485ca7c48ee1677f9680e3b59`。两套最终镜像的 GCC 可执行文件 SHA-256 一致，确认复用的是同一工具链产物。
5. 本次仍在原来的 x86_64 WSL2/Docker 主机完成，Python 3.12.3、Docker 29.1.3，构建并行度为 2；没有更换宿主机。

## 验证结果

| 检查 | Ubuntu 24.04 | Ubuntu 26.04 |
|---|---|---|
| 镜像构建 | 原始完整 Dockerfile，PASS | 原样开发阶段、共享 GCC，PASS |
| 新容器、默认普通用户 uid 1001 | PASS | PASS |
| C / C++ 编译及 Spike 执行 | PASS | PASS |
| 故意失败返回值检查 | PASS，预期 1 | PASS，预期 1 |
| 容器无网络时的基础执行 | PASS | PASS |
| uid 1000、挂载目录编译、退出后文件保留 | PASS | PASS |
| 额外 RV64GC/LP64D 整数及双精度运算探针 | PASS | PASS |
| libc.a / libstdc++.a 及记录文件存在性 | PASS | PASS |

额外运算探针使用验证目录中的启动代码，显式开启浮点状态；公开仓库原整数探针没有更改。这个检查增加基础运算覆盖，没有验证完整目标标准库。

## 证据与产物

- Ubuntu 24.04 镜像：`sha256:b70edf2c2f8425fa45f7e2b438b4d5a3346e7b84b5c0b6937d3460ecdbdfc7db`。
- Ubuntu 26.04 镜像：`sha256:541c1b99516a9358e083349fc93a746b1f3fa9bd0cc93b8ff46f461186a480cd`。
- 相同 GCC 可执行文件：`fed5890fb648b9f3bf7b6abfe441e41da406c60b558842bda4e229e2ceaa1556`。
- 完整编译日志和验证辅助 Dockerfile 保留在本地工作审计目录。下方提供精选运行日志。
- [机器可读结果](public-recheck-20261016.json)。

## 尚未覆盖

完整 ACT4 集成、认证、真实板卡、VM、完整 ISA/ABI、目标标准库运行测试和二进制逐字节可复现均未完成。完整原始 26.04 构建脚本没有单独从头跑完。本机缓存复用效率需要后续评估；本次没有修改公共构建入口来处理它。


## 精选日志

- [24.04 普通用户与无网络探针](public-recheck-24.04.log)
- [26.04 普通用户与无网络探针](public-recheck-26.04.log)
- [24.04 挂载与指定 UID](public-recheck-24.04-bind.log)
- [26.04 挂载与指定 UID](public-recheck-26.04-bind.log)
