import 'package:flutter_test/flutter_test.dart';
import 'package:carbide_shell/core/models.dart';
import 'package:carbide_shell/core/policy.dart';

void main() {
  group('审批策略', () {
    test('默认档：只读直接跑，写操作要问', () {
      final ApprovalPolicy p = ApprovalPolicy();
      expect(p.verdict(ToolRisk.read, 'ls -la'), ApprovalVerdict.allow);
      expect(p.verdict(ToolRisk.write, 'systemctl restart nginx'), ApprovalVerdict.ask);
    });

    test('全部放行档也不会放行危险命令', () {
      final ApprovalPolicy p = ApprovalPolicy(mode: ApprovalMode.autoAll);
      expect(p.verdict(ToolRisk.write, 'systemctl restart nginx'), ApprovalVerdict.allow);
      expect(p.verdict(ToolRisk.write, 'rm -rf /var/log'), ApprovalVerdict.deny);
      expect(p.verdict(ToolRisk.read, 'dd if=/dev/zero of=/dev/sda'), ApprovalVerdict.deny);
      expect(p.verdict(ToolRisk.write, 'shutdown -h now'), ApprovalVerdict.deny);
      expect(p.verdict(ToolRisk.write, 'echo x > /etc/passwd'), ApprovalVerdict.deny);
    });

    test('全部确认档：连读也问', () {
      final ApprovalPolicy p = ApprovalPolicy(mode: ApprovalMode.askAll);
      expect(p.verdict(ToolRisk.read, 'df -h'), ApprovalVerdict.ask);
    });

    test('空摘要不参与危险匹配', () {
      final ApprovalPolicy p = ApprovalPolicy();
      expect(p.verdict(ToolRisk.read, ''), ApprovalVerdict.allow);
    });
  });
}
