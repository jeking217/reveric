// 职责: 验证工具结果带图片时，OpenAI 兼容请求里 assistant(tool_calls) 之后
// 必须是连续完整的 tool 消息，图片补在整个工具轮结束后。
// 关联文件:
//   lib/shared/agent/client/openai_client.dart
//   lib/shared/agent/client/gemini_client.dart
//   lib/shared/services/ai/files/attachments.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/client/openai_client.dart';
import 'package:reveric/shared/agent/message.dart';

void main() {
  OpenAiClient buildClient() => OpenAiClient(
    apiKey: 'test',
    baseUrl: 'http://localhost:1',
    model: 'deepseek-v4-flash',
  );

  AgentMessage toolResult(String callId, {required bool withImage}) {
    return AgentMessage(
      id: 'tool_$callId',
      role: AgentMessageRole.user,
      type: AgentMessageType.tool_result,
      blocks: [
        ToolResultBlock(
          toolCallId: callId,
          toolName: 'Run',
          content: [
            const TextBlock('{"ok":true}'),
            if (withImage)
              const ImageBlock(data: 'AAAA', mimeType: 'image/png'),
          ],
        ),
      ],
    );
  }

  test('parallel tool results with images keep tool messages contiguous', () {
    final wire = buildClient().convertMessages([
      AgentMessage.user(id: 'u1', content: '生成两张图'),
      const AgentMessage(
        id: 'a1',
        role: AgentMessageRole.assistant,
        blocks: [
          ToolCallBlock(
            callId: 'c1',
            toolName: 'Run',
            arguments: {'prompt': 'a'},
          ),
          ToolCallBlock(
            callId: 'c2',
            toolName: 'Run',
            arguments: {'prompt': 'b'},
          ),
        ],
      ),
      toolResult('c1', withImage: true),
      toolResult('c2', withImage: true),
    ]);

    final roles = wire.map((m) => m.role).toList();
    expect(roles, ['user', 'assistant', 'tool', 'tool', 'user', 'user']);

    final toolIds = wire
        .where((m) => m.role == 'tool')
        .map((m) => m.toJson()['tool_call_id'])
        .toList();
    expect(toolIds, ['c1', 'c2']);

    // 图片只出现在工具轮结束之后：每个工具结果各补一条 user 消息，
    // tool 消息之间不再夹杂 user 消息。
    final trailing = wire.skip(wire.length - 2).toList();
    final imagesPerMessage = <int>[];
    for (final message in trailing) {
      final json = message.toJson();
      expect(json['role'], 'user');
      final parts = json['content'] as List<dynamic>;
      imagesPerMessage.add(
        parts.whereType<Map>().where((p) => p['type'] == 'image_url').length,
      );
    }
    expect(imagesPerMessage, [1, 1]);
  });

  test('image-only result still keeps a single tool message per call', () {
    final wire = buildClient().convertMessages([
      AgentMessage.user(id: 'u1', content: '看图'),
      const AgentMessage(
        id: 'a1',
        role: AgentMessageRole.assistant,
        blocks: [
          ToolCallBlock(callId: 'c1', toolName: 'Run', arguments: {}),
        ],
      ),
      AgentMessage(
        id: 'tool_c1',
        role: AgentMessageRole.user,
        type: AgentMessageType.tool_result,
        blocks: [
          const ToolResultBlock(
            toolCallId: 'c1',
            toolName: 'Run',
            content: [ImageBlock(data: 'AAAA', mimeType: 'image/png')],
          ),
        ],
      ),
    ]);

    final roles = wire.map((m) => m.role).toList();
    expect(roles, ['user', 'assistant', 'tool', 'user']);
    expect(
      (wire[2].toJson())['content'],
      '(see attached image)',
    );
  });
}
