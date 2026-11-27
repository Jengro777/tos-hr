import 'package:material_ui/material_ui.dart';

import '../auth/auth_service.dart';
import '../theme/tospino_hr_style.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.onAuthenticated,
    this.allowDebugSkip = false,
    this.authService = const AuthService(),
  });

  final VoidCallback onAuthenticated;
  final bool allowDebugSkip;
  final AuthService authService;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            if (!wide) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 30),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 60,
                  ),
                  child: Center(child: _buildLoginPanel(mobile: true)),
                ),
              );
            }
            return Row(
              children: [
                Expanded(flex: 9, child: _buildBrandPanel()),
                Expanded(
                  flex: 11,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 36,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 72,
                      ),
                      child: Center(child: _buildLoginPanel()),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBrandPanel() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(42),
      decoration: BoxDecoration(
        color: TospinoHrColors.ink,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x301C1C1C),
            blurRadius: 40,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _LoginLogoMark(size: 54, dark: true),
          const Spacer(),
          const Text(
            'ATTENDANCE · PEOPLE OPS',
            style: TextStyle(
              color: TospinoHrColors.ink4,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '让每一次出勤，\n都清晰可追溯。',
            style: TextStyle(
              color: Colors.white,
              fontSize: 36,
              height: 1.25,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.2,
            ),
          ),
          const SizedBox(height: 18),
          const SizedBox(
            width: 420,
            child: Text(
              '统一管理企业微信打卡记录、月度考勤与年度汇总，'
              '通过 TiDB 统一保存打卡记录与汇总结果。',
              style: TextStyle(
                color: Color(0xFFB8B7B3),
                fontSize: 13,
                height: 1.7,
              ),
            ),
          ),
          const Spacer(),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: const [
              _FeaturePill(icon: Icons.sync_rounded, label: '增量同步'),
              _FeaturePill(icon: Icons.storage_rounded, label: 'TiDB 统计'),
              _FeaturePill(icon: Icons.shield_outlined, label: '凭据保护'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoginPanel({bool mobile = false}) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 430),
      padding: EdgeInsets.all(mobile ? 24 : 32),
      decoration: BoxDecoration(
        color: TospinoHrColors.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: TospinoHrColors.line),
        boxShadow: TospinoHrShadows.card,
      ),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (mobile) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: _LoginLogoMark(size: 50),
                ),
                const SizedBox(height: 22),
              ],
              const Text('欢迎回来', style: TospinoHrText.pageTitle),
              const SizedBox(height: 7),
              const Text('登录后进入企业微信考勤数据中心。', style: TospinoHrText.meta),
              const SizedBox(height: 26),
              const _InputLabel('账号'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _accountController,
                enabled: true,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(
                  hintText: '请输入账号',
                  prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入账号' : null,
                onFieldSubmitted: (_) => _passwordFocusNode.requestFocus(),
              ),
              const SizedBox(height: 18),
              const _InputLabel('密码'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _passwordController,
                focusNode: _passwordFocusNode,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  hintText: '请输入密码',
                  prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                    tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                    ),
                  ),
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? '请输入密码' : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.topCenter,
                child: _errorMessage == null
                    ? const SizedBox(height: 20)
                    : Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: TospinoHrColors.dangerTint,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: TospinoHrColors.dangerBorder,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: TospinoHrColors.danger,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TospinoHrText.meta.copyWith(
                                    color: TospinoHrColors.danger,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: TospinoHrColors.brand,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('登录'),
                      SizedBox(width: 7),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ),
              ),
              if (widget.allowDebugSkip) ...[
                const SizedBox(height: 11),
                SizedBox(
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: widget.onAuthenticated,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: TospinoHrColors.ink,
                      side: const BorderSide(color: TospinoHrColors.line),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    icon: const Icon(Icons.developer_mode_rounded, size: 18),
                    label: const Text('Debug 跳过登录'),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_rounded,
                    size: 13,
                    color: TospinoHrColors.ink4,
                  ),
                  SizedBox(width: 5),
                  Text('密码经摘要校验，不在客户端保存明文', style: TospinoHrText.meta),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final authenticated = widget.authService.authenticate(
      account: _accountController.text,
      password: _passwordController.text,
    );
    if (!authenticated) {
      setState(() => _errorMessage = '账号或密码错误，请重新输入');
      return;
    }
    setState(() => _errorMessage = null);
    widget.onAuthenticated();
  }
}

class _InputLabel extends StatelessWidget {
  const _InputLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TospinoHrText.eyebrow.copyWith(
        color: TospinoHrColors.ink3,
        letterSpacing: 0.2,
        fontSize: 11,
      ),
    );
  }
}

class _LoginLogoMark extends StatelessWidget {
  const _LoginLogoMark({required this.size, this.dark = false});

  final double size;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF292928) : TospinoHrColors.surface,
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(
          color: dark ? const Color(0xFF3B3B39) : TospinoHrColors.line,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: -0.45,
            child: Container(
              width: size * 0.52,
              height: size * 0.23,
              decoration: BoxDecoration(
                color: dark ? Colors.white : TospinoHrColors.ink,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          Positioned(
            bottom: size * 0.17,
            child: Container(
              width: size * 0.56,
              height: size * 0.18,
              decoration: BoxDecoration(
                color: TospinoHrColors.brandLight,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0x24FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFFD5D4D0)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFD5D4D0),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
