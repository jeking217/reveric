// 职责: 应用级别编译期常量（版本号、功能开关、产品线、匿名上报地址、反馈渠道、匿名诊断公共头）
// 关联文件:
//   lib/shared/providers/trace_providers.dart
//   lib/shared/providers/anonymous_reporting_providers.dart
//   lib/shared/logger/startup_failure_reporter.dart
//   lib/shared/widgets/ai/chat/feedback_dialog.dart
//   release.sh (版本号同步)
//

/// 应用版本号。
/// 与 pubspec.yaml 的 version 字段保持同步，由 release.sh 一同更新。
/// 供需要同步获取版本号的场景使用（如匿名上报），避免 PackageInfo 异步调用。
const appVersion = '0.7.0';

/// 产品展示名。窗口标题、安装包元数据与界面文案统一使用它。
/// 可执行文件名仍为 `reveric.exe`，构建、更新与单实例链路都依赖该文件名。
const appDisplayName = 'Unione AI Drama';

/// 匿名诊断接收地址，包含完整路径；请求不追加业务 API 后缀。
/// 为空表示本构建不接匿名诊断：不上报，也不展示 opt-in 入口。
const anonymousReportingBaseUrl = '';

/// 公开仓库地址，供关于页展示项目主页。
const revericGitHubRepoUrl = 'https://github.com/looplj/reveric';

/// QQ 交流群官方邀请链接。
const revericQqGroupJoinUrl = 'https://qm.qq.com/q/Ap8pfOWHDO';
const revericQqGroupNumber = '924148054';

/// 技能广场只读取公开链接目录，导入沿用各来源平台的现有流程。
const revericSkillsCatalogUrl =
    'https://raw.githubusercontent.com/looplj/reveric-skills/main/catalog.json';

/// AGPLv3 第 7 条附加条款要求修改版保留的作者署名，与 NOTICES 保持一致，不做本地化。
const revericAttribution = 'Based on Reveric by looplj.';

/// 接收用户通过邮件私下发送的反馈与诊断文件。
const revericFeedbackEmail = 'bababaa261@gmail.com';

/// 产品线编码，通过 X-Product-Code 请求头发送给匿名诊断接收端。
const revericProductCode = 'writer';

/// 匿名诊断 API 公共请求头。
final revericApiHeaders = <String, String>{
  'Content-Type': 'application/json',
  'X-Product-Code': revericProductCode,
};

/// 用户主动提交日志与会话的诊断后端，与匿名事件上报独立。
const diagnosticsBaseUrl = 'https://diagnostics.reveric.app';

/// 构思画布的 UI、工具与内置技能入口；不影响视频制作画布。
const ideationCanvasEnabled = bool.fromEnvironment(
  'ENABLE_IDEATION_CANVAS',
  defaultValue: false,
);

/// Unione 平台门户地址，含 context path：`https://host/portal`，不是网关。
/// 登录页允许就地修改并保存在本地，这里只是首次启动时的默认值。
const unioneDefaultPortalUrl = String.fromEnvironment(
  'UNIONE_PORTAL_URL',
  defaultValue: 'https://online.unione.cloud/portal',
);

/// Unione 登录表单加密密码用的 SM2 公钥（十六进制，04 开头）。
/// 默认值与平台内置的 `secret.soft.sm2keys` 一致；平台轮换密钥后用
/// `--dart-define=UNIONE_SM2_PUBLIC_KEY=...` 覆盖。
const unioneSm2PublicKey = String.fromEnvironment(
  'UNIONE_SM2_PUBLIC_KEY',
  defaultValue:
      '04a684d7140aebfc83515a2312dac7ab836f3adc484627971b6936ad7d5575048c'
      'aecf9c7eb07ed4dcee9d04cb3a7b1c514477b646b1ebe8245de215733baa5133',
);
