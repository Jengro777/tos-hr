set shell := ["bash", "-cu"]

local_config := ".dart_tool/local_dart_defines.json"

default:
    @just --list

# 在本机 Linux 窗口中运行
prepare-config:
    dart run tool/dart_defines.dart

run: prepare-config
    flutter run -d linux --dart-define-from-file={{local_config}}

# 运行静态分析
analyze:
    flutter analyze

# 运行测试
test:
    flutter test

# 构建 Linux 发布包
build-linux: prepare-config
    flutter build linux --release --dart-define-from-file={{local_config}}

# 构建 Web 发布包
build-web:
    flutter build web
