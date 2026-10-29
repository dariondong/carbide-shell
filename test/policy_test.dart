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

    test('全部放行档也不会放行会把机器弄坏的命令', () {
      final ApprovalPolicy p = ApprovalPolicy(mode: ApprovalMode.autoAll);
      expect(p.verdict(ToolRisk.write, 'systemctl restart nginx'), ApprovalVerdict.allow);
      expect(p.verdict(ToolRisk.read, 'dd if=/dev/zero of=/dev/sda'), ApprovalVerdict.deny);
      expect(p.verdict(ToolRisk.write, 'shutdown -h now'), ApprovalVerdict.deny);
      expect(p.verdict(ToolRisk.write, 'echo x > /etc/passwd'), ApprovalVerdict.deny);
      expect(p.verdict(ToolRisk.write, 'mkfs.ext4 /dev/sda1'), ApprovalVerdict.deny);
      expect(p.verdict(ToolRisk.write, 'rm -rf /'), ApprovalVerdict.deny);
      expect(p.verdict(ToolRisk.write, 'rm -rf /*'), ApprovalVerdict.deny);
      expect(p.verdict(ToolRisk.write, 'rm -rf ~'), ApprovalVerdict.deny);
    });

    test('删东西的命令要问，问过就做', () {
      final ApprovalPolicy p = ApprovalPolicy(mode: ApprovalMode.autoAll);
      expect(p.verdict(ToolRisk.write, 'rm -rf /var/log'), ApprovalVerdict.ask);
      expect(p.verdict(ToolRisk.write, 'rm 旧日志.txt'), ApprovalVerdict.ask);
      expect(p.verdict(ToolRisk.write, 'rmdir /srv/old'), ApprovalVerdict.ask);
      expect(p.verdict(ToolRisk.write, 'find /tmp -name "*.log" -delete'),
          ApprovalVerdict.allow);
      expect(p.isRisky('rm -rf /var/log'), isTrue);
      expect(p.isDangerous('rm -rf /var/log'), isTrue);
      expect(p.isDangerous('df -h'), isFalse);
    });

    test('删到根与删到别的目录分得清', () {
      final ApprovalPolicy p = ApprovalPolicy(mode: ApprovalMode.autoAll);
      expect(p.isBlocked('rm -rf /'), isTrue);
      expect(p.isBlocked('rm -rf /var'), isFalse);
      expect(p.isBlocked('rm -rf ~/projects'), isFalse);
      expect(p.isBlocked('rm -rf ~/*'), isTrue);
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
