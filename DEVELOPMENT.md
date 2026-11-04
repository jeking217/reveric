# 开发与构建

本指南面向从源码运行和打包 Unione AI Drama 的开发者。支持 Windows、macOS、Android；桌面应用需要在对应操作系统上构建。当前发布架构为 macOS arm64、Windows x64、Android arm64-v8a。

除特别注明外，命令均在仓库根目录执行。本地 Flutter 命令统一使用 `fvm flutter`，避免误用系统 PATH 中的其他 SDK。

## 环境与版本

| 工具 | 要求 | 配置来源 |
| --- | --- | --- |
| Flutter | 提交 `0b771a584214b44aa1f94f9707f2756207356f41`，由 FVM 安装 | [.fvmrc](.fvmrc) |
| Dart | 使用上述 Flutter SDK 自带版本 | 无需单独安装项目用 Dart |
| Rust | `1.99.1`，通过 rustup 安装 | [FJS 构建配方](third/fjs/libfjs/cargokit.yaml)、[Android 工具链](third/irondash_engine_context/android/rust/rust-toolchain.toml) |
| Python | 建议 `3.12`，与 CI 一致；终端可执行 `python3` | [.github/workflows/build.yaml](.github/workflows/build.yaml) |
| Git | 获取源码、Git 依赖和原生库源码 | [pubspec.yaml](pubspec.yaml) |
| CMake | 桌面深度估计运行时要求至少 `3.20` | [CMakeLists.txt](third/depth-native/CMakeLists.txt) |
| Clang / libclang | 需要运行 bindgen 生成 C 绑定时准备；当前 Windows x64 原生构建使用已有绑定 | [bindgen 环境说明](https://rust-lang.github.io/rust-bindgen/requirements.html) |
| Fastforge | 打包桌面安装包时使用 `0.6.6` | CI 与 macOS 打包脚本 |

Flutter 使用固定提交，不能用 `stable` 或 `master` 的最新版本替代。升级 Flutter 时同步修改 `.fvmrc` 和 CI 中的 `FLUTTER_VERSION`；升级 Rust 时同步检查 FJS 配方、产物校验脚本、Android 工具链和 CI。

首次安装需要联网访问 Flutter、pub.dev、crates.io、GitHub 和目标平台的软件源。`third/` 下包含本地依赖修改，保留完整目录，不要替换成同名的公开包。

## 获取源码与安装工具链

先按 [FVM 安装说明](https://fvm.app/documentation/getting-started/installation) 和 [rustup 安装说明](https://rustup.rs/) 安装工具，并确认 `fvm`、`rustup`、`cargo` 在 PATH 中。

```sh
git clone https://github.com/looplj/reveric.git
cd reveric

fvm install --skip-pub-get
fvm use --skip-pub-get
rustup toolchain install 1.99.1 --profile default

fvm flutter --version
rustc +1.99.1 --version
fvm flutter pub get
fvm flutter doctor -v
```

`fvm use` 不带版本号时读取项目配置，并建立 `.fvm/flutter_sdk` 链接。安装后检查 `.fvmrc`，保留仓库中的完整提交号。IDE 的 Flutter SDK 路径也设置为 `.fvm/flutter_sdk`。

项目构建入口显式选择 Rust `1.99.1`，不要求修改全局默认工具链。直接调用 Cargo 时使用 `cargo +1.99.1 ...`。

## macOS

### 环境准备

使用 Apple Silicon Mac，安装完整 Xcode，并在 Xcode 中安装 macOS、iOS 和 iOS Simulator 所需组件。CI 固定 Xcode `26.2`；本地其他版本需自行验证。仅安装 Command Line Tools 不足以完成本项目的 Apple 归档构建。

安装 CMake、Ninja、Python 3；使用 Makefile 时还需要 `make`。打包 DMG 时需要 Node.js、npm 和 appdmg。

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch

xcodebuild -version
xcrun --sdk macosx --show-sdk-version
xcrun --sdk iphoneos --show-sdk-version
xcrun --sdk iphonesimulator --show-sdk-version

rustup target add --toolchain 1.99.1 aarch64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim
```

虽然应用当前不发布 iOS 版本，FJS 的本地 XCFramework 仍包含 macOS、iOS 真机和模拟器三个切片，因此三个 Rust target 和对应 SDK 都需要准备。

首次构建、清理 `build/` 后，或更新深度估计原生依赖后，先准备 CPU 运行时。此步骤会下载并编译裁剪后的 ONNX Runtime，首次耗时较长。

```sh
bash third/depth-native/prepare-product-macos.sh
```

### 运行与构建

```sh
make run-macos
make build-macos
make build-macos-release
```

三个目标分别用于调试运行、Debug 构建和 Release 构建。它们会先构建或复用 FJS 归档，并准备视频播放所需的 MDK，再调用 FVM Flutter。

构建结果位于：

- Debug：`build/macos/Build/Products/Debug/Unione AI Drama.app`
- Release：`build/macos/Build/Products/Release/Unione AI Drama.app`

排查 FJS 产物时，可单独执行：

```sh
bash third/fjs/tool/build_runtime.sh
bash third/fjs/tool/build_runtime.sh --verify
bash third/fjs/tool/build_runtime.sh --verify-app "build/macos/Build/Products/Debug/Unione AI Drama.app"
```

项目禁用了上游 FJS 预编译包下载，归档从当前源码生成，并校验源码、工具链和校验和。原生构建失败时应处理实际错误，不要换用上游二进制绕过。

### 打包 DMG 与 ZIP

```sh
bash build-macos.sh
# 可选：指定版本号
bash build-macos.sh 1.2.3+42
```

脚本准备 Fastforge `0.6.6`、appdmg 和原生依赖，输出 DMG 与 ZIP 到 `dist/`。它会临时调整 `pubspec.yaml`，退出时还原；执行过程中不要同时修改该文件。脚本会清理 `dist/` 中旧的 DMG 和 ZIP，需保留的安装包请提前移走。

## Windows

### 环境准备

在 Windows x64 上安装 Visual Studio 的“使用 C++ 的桌面开发”工作负载，包含 MSVC、Windows SDK 和 CMake 工具。Visual Studio Code 不能替代这套原生编译工具。[Flutter Windows 环境说明](https://docs.flutter.dev/platform-integration/windows/setup)

同时准备 Git、FVM、rustup、Python 和可从终端调用的 CMake。Flutter 插件需要符号链接支持，请开启 Windows 开发者模式。以下命令使用 PowerShell：

```powershell
rustup target add --toolchain 1.99.1 x86_64-pc-windows-msvc
fvm flutter doctor -v
fvm flutter devices

# 首次构建或清理 build/ 后准备深度估计运行时
.\third\depth-native\prepare-product-windows.ps1
```

当前锁定的 rquickjs 在宿主与目标一致、已有对应绑定且未启用 `update-bindings` 时，直接复制绑定文件并跳过 bindgen。Windows x64 原生构建满足这些条件，因此无需为 FJS 单独安装 LLVM。交叉编译或主动重新生成绑定时，再按 bindgen 要求准备 libclang。[rquickjs 构建逻辑](https://github.com/DelSkayn/rquickjs/blob/3d5ecfc94e3f9ea3a9769422ca718a7dd063e00f/sys/build.rs)

Windows CI 使用 GitHub 托管的 `windows-latest`，工作流没有额外安装 LLVM 或设置 `LIBCLANG_PATH`；托管镜像本身预装 LLVM。不能仅凭 CI 构建成功判断本地机器需要哪些额外工具，应以实际构建路径为准。[Runner 软件清单](https://github.com/actions/runner-images)

### 运行与构建

```powershell
fvm flutter run -d windows
fvm flutter build windows --debug
fvm flutter build windows --release
```

产物在 `build/windows/x64/runner/Debug/` 或 `Release/`。分发未打包的应用时需要保留整个输出目录，包括 DLL 和 `data/`。

### 打包 EXE

安装 Inno Setup 6，将 Dart 全局可执行文件目录加入 PATH。脚本还会准备 Inno Setup 中文语言文件和 VC++ 可再发行组件；写入 Inno Setup 安装目录可能需要管理员权限。

```powershell
fvm dart pub global activate fastforge 0.6.6
fvm exec powershell -NoProfile -File .\build-windows.ps1
# 可选：指定版本号
fvm exec powershell -NoProfile -File .\build-windows.ps1 -Version "1.2.3+42"
```

Windows 打包脚本内部直接调用 `flutter`、`dart` 和 `fastforge`，因此通过 `fvm exec` 启动，让这些命令使用项目 SDK。脚本会清理 `dist/` 中旧的 EXE，临时修改并还原 `pubspec.yaml`，最终安装包输出到 `dist/`。

## Android

### 环境准备

安装 JDK `17`、Android Studio，以及 SDK Platform、Build-Tools、Platform-Tools、Command-line Tools、NDK 和 CMake。[Flutter Android 环境说明](https://docs.flutter.dev/platform-integration/android/setup)

当前锁定 Flutter SDK 的默认值为：

| 配置 | 值 |
| --- | --- |
| compileSdk / targetSdk | `36` |
| minSdk | `24` |
| NDK | `28.2.13676358` |
| Gradle Wrapper | `9.5.0` |
| Android Gradle Plugin | `9.0.1` |

SDK 与 NDK 取自 Flutter 的 `FlutterExtension.kt`；应用在 [android/app/build.gradle.kts](android/app/build.gradle.kts) 中引用这些默认值。Gradle 由仓库 Wrapper 下载，无需单独安装。

```sh
rustup target add --toolchain 1.99.1 aarch64-linux-android
fvm flutter doctor --android-licenses
fvm flutter doctor -v
fvm flutter devices
```

使用 arm64 Android 真机或匹配架构的模拟器；当前应用 ABI 配置仅包含 `arm64-v8a`。设备开启 USB 调试后，将下方占位符替换成 `fvm flutter devices` 输出的设备 ID：

```sh
fvm flutter run -d <device-id>
```

### 构建 APK

在 Bash 环境运行；Windows 可使用 Git Bash，并确保它能找到 FVM、Python 3 和 Android 工具链。

```sh
bash build-android.sh
# 可选：指定版本号
bash build-android.sh 1.2.3+42
```

脚本构建 Release arm64 APK，处理 SQLite hook 和产物路径校验，输出到 `dist/<版本号>/reveric-android-arm64-v8a-v<版本号>.apk`。它会备份并还原 `pubspec.yaml`。构建期间不要并行运行其他 Flutter 命令，以免重写插件注册文件。

正式发布前配置本机 `android/key.properties`，例如：

```properties
storeFile=release.keystore
storePassword=YOUR_STORE_PASSWORD
keyAlias=YOUR_KEY_ALIAS
keyPassword=YOUR_KEY_PASSWORD
```

相对的 `storeFile` 从 `android/` 解析。签名文件和密码不入库，并持续使用同一签名以支持覆盖升级。未配置时，本地 Release 构建会使用 Debug 签名，只适合本机测试；CI 发布要求配置对应的 Android 签名 secrets。

## Unione 平台登录

应用启动后先校验本地登录态：有会话直接进入工作台，没有会话则停在欢迎页，登录表单就在原来那张入口卡片里（不再单独加一屏登录页），账号密码通过 Unione 门户鉴权。

- 密码在设备本地用平台 SM2 公钥加密（SM2/SM3 纯 Dart 实现），明文不出本机；图形验证码直接向门户取图，按 `CAPTCHAID` 回传。
- 登录成功后会话（令牌、用户、租户、时间）写入 `shared_preferences` 的 `unione.session.v1`，重启无需重复登录。
- 平台身份即本地身份：登录成功会直接用平台显示名作为本地称呼并标记引导完成，不会再让人填一遍昵称/头像（之后可在用户资料里改）。
- 门户拒绝时直接展示平台返回的中文提示（如密码错误、账号锁定）；网络层失败与凭据错误分开提示。

门户地址与公钥默认值在 [lib/shared/app_config.dart](lib/shared/app_config.dart)，构建时可用 dart-define 覆盖：

```sh
fvm flutter run -d windows \
  --dart-define=UNIONE_PORTAL_URL=https://online.unione.cloud/portal \
  --dart-define=UNIONE_SM2_PUBLIC_KEY=04...
```

### 从 AgenticOS 带票启动

AgenticOS 的「AI 短剧」入口会用一张一次性票据把本应用拉起来，省掉再登录一次：

```sh
reveric.exe --unione-ticket tk-<32位十六进制> --unione-issuer http://10.0.0.7:3000
```

- 有票据且本地没有会话：向 `{issuer}/api/drama/access?accessToken=…` 核销，换到身份后写入本地会话，直接进工作台。
- 本地已有会话：票据不核销（票据是一次性的，白花掉只会让签发方以为这次交接失败），照常进工作台。
- 票据无效、过期、已用过，或参数不成形：停在欢迎页的登录表单，横幅里说明原因（平台原话或参数问题），用户照常手动登录。
- 环境变量 `UNIONE_TICKET` / `UNIONE_ISSUER` 可代替这两个参数，供不方便改命令行的启动器使用。票据不进日志。

运行期也可在登录页底部的「服务器地址」临时切换门户，选择会写入 `unione.portal_url.v1` 并在下次启动复用；桌面端「设置 → 账户」可查看当前登录、所属组织与登录时间，或退出登录。

相关实现集中在 [lib/shared/services/unione/](lib/shared/services/unione/)（SM2/SM3、门户客户端、会话存储）与 [lib/shared/widgets/auth/](lib/shared/widgets/auth/)（登录页、门户地址弹窗、登录门禁）。当前只接入账号密码登录，未接入一次性令牌（ticket）免登。

```sh
fvm flutter test test/shared/services/unione test/shared/models/unione_session_test.dart
```

## 代码生成与检查

修改 Riverpod、Drift、JSON 序列化等生成源后执行：

```sh
make codegen
# 没有 make 时使用等价命令
fvm flutter pub run build_runner build --delete-conflicting-outputs
```

检查生成文件的 diff 后，再运行受影响范围的测试。Flutter 测试串行执行：

```sh
fvm flutter analyze
fvm flutter test test/path/to/affected_test.dart
```

将测试路径替换成实际文件；Widget 测试在安装了 `timeout` 的终端中使用 `timeout 300 fvm flutter test ...` 限制运行时间。完整测试集使用 `fvm flutter test`，不要与其他 Flutter 测试或 Android 打包同时运行。

验证 FJS 工具链选择和产物缓存的定点命令：

```sh
cd third/fjs/cargokit/build_tool
fvm flutter pub run test test/builder_test.dart
cd ../../../..
python3 -m unittest discover -s third/fjs/tool -p artifact_test.py
```

## 常见构建问题

- **Rust 报 E0463 或 `mis-aligned LINKEDIT string pool`**：确认构建使用 `1.99.1`，而非旧版本。macOS 27 上该错误可能来自 LLVM 剥离符号时的对齐缺陷，见 [Rust #157750](https://github.com/rust-lang/rust/issues/157750)。更新工具链后重新执行 FJS 构建脚本。
- **缺少 Apple target 或 SDK**：核对 `rustup target list --installed --toolchain 1.99.1` 和上面的 `xcrun` 命令。只安装 macOS target 无法生成当前 FJS 归档。
- **bindgen 提示找不到 libclang**：先确认是否在交叉编译、重新生成绑定或使用了不同依赖版本。确需生成绑定时，按 bindgen 环境说明安装 LLVM，并配置可由宿主机加载的 libclang。Android 构建由 CargoKit 设置 NDK 的 Clang 和 sysroot，不要在未核对实际报错前用全局 LLVM 环境变量覆盖这些配置。
- **提示 `Depth SDK missing` 或 `Depth runtime missing`**：执行对应平台的 `prepare-product-*` 脚本。`make clean` 或 `fvm flutter clean` 清理 `build/` 后也需要重新准备。
- **Flutter 版本不一致**：检查 `fvm flutter --version`、IDE SDK 路径和 `.fvmrc`。CI 不使用 FVM，由工作流安装同一个提交并直接调用 Flutter。
- **测试后出现无关依赖变更**：检查 `pubspec.lock` 的 diff，尤其是本地镜像源 URL 和自动解析的依赖版本；不要将无关变化混入功能提交。

构建和打包入口以 [Makefile](Makefile)、各平台脚本及 [CI 工作流](.github/workflows/build.yaml) 为准。升级工具链或调整入口时，同步维护本文件。


## 贡献

提交 Pull Request（PR）前，请阅读 [贡献者许可协议（CLA）](CLA.md)。提交 PR 即表示同意该协议，允许维护者将你的贡献用于商业闭源版本及再许可；你保留贡献的版权。

## 附录：本地源码运行速查

上面的章节按平台拆分了环境细节，这里把「拉下源码到界面跑起来」压成一条最短路径。命令均在仓库根目录执行，Flutter 一律走 `fvm flutter`。

### Windows（本地 Windows x64 + VS 2022 Build Tools 实测通过）

```powershell
git clone https://github.com/looplj/reveric.git
cd reveric

fvm install --skip-pub-get
fvm use --skip-pub-get
rustup toolchain install 1.99.1 --profile default
rustup target add --toolchain 1.99.1 x86_64-pc-windows-msvc
fvm flutter pub get

# 首次构建、或执行过 fvm flutter clean / make clean 之后需要准备深度估计运行时
.\third\depth-native\prepare-product-windows.ps1

# 启动调试（首次会编译原生部分，耗时较长；之后走增量）
fvm flutter run -d windows
```

启动成功后终端会输出 `Flutter run key commands`，同时弹出应用窗口并出现 `reveric.exe` 进程。交互键：`r` 热重载、`R` 热重启、`q` 退出。

项目通过 `pubspec.yaml` 的 path 依赖引用 `third/` 下的本地包（如 `window_manager`），`pub get` 会一并解析，不需要单独安装或替换成同名的公开包。`lib/**/*.g.dart` 生成文件已入库，**日常运行不需要先跑代码生成**；只有改动了 Riverpod Provider、Drift 表结构或 JSON 序列化注解之后，才执行 `make codegen`（没有 make 时用 `fvm flutter pub run build_runner build --delete-conflicting-outputs`）。

### macOS / Android

macOS 需要先准备 Xcode 与 CPU 运行时，再 `make run-macos`；Android 需要 arm64 设备或模拟器，再 `fvm flutter run -d <device-id>`。前置条件和多切片 Rust target 见上文 [macOS](#macos) 与 [Android](#android) 章节。

### 只跑构建产物、不挂调试器

```powershell
fvm flutter build windows --debug     # 产物：build\windows\x64\runner\Debug\reveric.exe
fvm flutter build windows --release   # 产物：build\windows\x64\runner\Release\reveric.exe
```

`build\windows\x64\runner\<模式>\` 目录需要整体分发，直接拷 exe 会因缺少 DLL 与 `data\` 启动失败。

### 本仓库实测结果

| 命令 | 结果 |
| --- | --- |
| `fvm flutter --version` | Flutter `3.50.0-0.3.pre`（commit `0b771a58`），Dart `3.14.0` |
| `fvm flutter pub get` | 依赖解析成功，`window_manager` 等以 path override 引入 |
| `fvm flutter analyze` | 0 error / 0 warning（其余为既有风格提示） |
| `fvm flutter build windows --debug` | 成功，约 4~5 分钟（含原生插件编译） |
| `fvm flutter run -d windows` | 成功，约 2 分钟起窗（复用已有 Debug 产物时更快） |

### 测试前先处理代理

本机设置了 `HTTP_PROXY`/`HTTPS_PROXY` 时，`flutter_tester` 与测试进程之间的本地 WebSocket 会被代理拦截，表现为整批测试在加载阶段就报 `Invalid WebSocket upgrade request`。跑测试前清掉代理并放行回环地址：

```sh
unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy
export NO_PROXY=localhost,127.0.0.1,::1
fvm flutter test
```

### 运行相关常见问题

- **Widget 测试整文件报缺少 `InternalFlutterWindows_WindowManager_Initialize`**：这是当前固定 Flutter 版本在 Windows 上运行 widget 测试时的框架侧限制（原生窗口管理符号未随 `flutter_tester` 提供），与本仓库代码无关。受影响的是 `testWidgets` 用例，纯 Dart 单元测试不受影响；需要完整跑 widget 测试时请在 CI 或 macOS 上执行。
- **`flutter pub get` 卡住或超时**：Flutter 资源下载走 `FLUTTER_STORAGE_BASE_URL`，国内网络可设置镜像后重试，例如 `https://storage.flutter-io.cn`。
- **启动后窗口空白或提示未配置模型**：应用不内置 API Key，需在「设置 ➔ 模型设置」中自行添加供应商并测试连通；作品数据全部存本地（SQLite 与工程文件夹）。
- **首次 `prepare-product-windows.ps1` 很慢**：该脚本会下载并裁剪 ONNX Runtime，只在首次以及清理 `build/` 后需要重跑，日常改代码不必重复执行。
