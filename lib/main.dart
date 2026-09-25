import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'account_service.dart';
import 'gift_card_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'local_service.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;

const greenColor = Color(0xFF16845A);
const darkTextColor = Color(0xFF26332B);
const grayTextColor = Color(0xFF68756E);
const borderColor = Color(0xFFE1E8E2);
const goldColor = Color(0xFFFFD36A);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const GiftCheckApp());
}

// ------------------------------------------------------------
// FUNCIONES AUXILIARES
// ------------------------------------------------------------

String money(String amount) {
  return r'$ ' + amount;
}

String formatDate(DateTime date) {
  const months = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  return date.day.toString() +
      ' de ' +
      months[date.month - 1] +
      ' del ' +
      date.year.toString();
}

TextStyle giftCardValueTextStyle() {
  return GoogleFonts.montserrat(
    color: Colors.black,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );
}

// Tipografía y tamaño únicos para las etiquetas doradas
// (VALOR:, PARA:, DE PARTE DE:) que acompañan a cada dato.
TextStyle giftCardLabelTextStyle() {
  return GoogleFonts.montserrat(
    color: const Color(0xFFC9A45C),
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );
}

String qrDataForGiftCard(GiftCard giftCard) {
  final expirationText = giftCard.expirationDate == null
      ? 'Sin vencimiento'
      : formatDate(giftCard.expirationDate!);

  return 'GiftCheck|'
      '${giftCard.code}|'
      'Importe:${giftCard.amount}|'
      'Vence:$expirationText';
}

bool isGiftCardExpired(DateTime? expirationDate) {
  if (expirationDate == null) {
    return false;
  }

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final expirationDay = DateTime(
    expirationDate.year,
    expirationDate.month,
    expirationDate.day,
  );

  return today.isAfter(expirationDay);
}

String effectiveGiftCardStatus(String status, DateTime? expirationDate) {
  if ((status == 'Activa' || status == 'Parcialmente usada') &&
      isGiftCardExpired(expirationDate)) {
    return 'Vencida';
  }

  return status;
}

InputDecoration appInputDecoration({
  required String label,
  String? hint,
  IconData? prefixIcon,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: borderColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: greenColor, width: 2),
    ),
  );
}

// ------------------------------------------------------------
// MODELO
// ------------------------------------------------------------

class GiftCard {
  final String code;
  final String amount;
  final DateTime? expirationDate;
  final String dedication;
  final String senderName;
  final String recipientName;
  final String status;

  const GiftCard({
    required this.code,
    required this.amount,
    required this.expirationDate,
    required this.dedication,
    required this.status,
    this.senderName = '',
    this.recipientName = '',
  });

  String get displayStatus => effectiveGiftCardStatus(status, expirationDate);

  GiftCard copyWith({
    String? status,
    String? recipientName,
    String? senderName,
  }) {
    return GiftCard(
      code: code,
      amount: amount,
      expirationDate: expirationDate,
      dedication: dedication,
      status: status ?? this.status,
      senderName: senderName ?? this.senderName,
      recipientName: recipientName ?? this.recipientName,
    );
  }
}

class GiftCardUsage {
  final String giftCardCode;
  final String amountUsed;
  final String username;
  final DateTime? usedAt;

  const GiftCardUsage({
    required this.giftCardCode,
    required this.amountUsed,
    required this.username,
    required this.usedAt,
  });
}

// ------------------------------------------------------------
// APP
// ------------------------------------------------------------
Future<void> showUsageReceipt({
  required BuildContext context,
  required String code,
  required String username,
  required String originalAmount,
  required String usedAmount,
  required String remainingAmount,
  required String status,
  VoidCallback? onBlock,
  VoidCallback? onCancel,
  VoidCallback? onReactivate,
}) async {
  final usages = await GiftCardService().loadGiftCardUsages(code);

  final receiptText = StringBuffer();

  receiptText.writeln('GiftCheck');
  receiptText.writeln('Comprobante de uso');
  receiptText.writeln('');
  receiptText.writeln('Gift Card: $code');
  receiptText.writeln('Valor total: ${money(originalAmount)}');
  receiptText.writeln('');
  receiptText.writeln('Usos registrados:');

  for (final usage in usages) {
    receiptText.writeln(
      '- ${money(usage['amountUsed'] ?? '0')}'
      ' · ${usage['username'] ?? ''}'
      ' · ${formatUsageDate(usage['usedAt'])}',
    );
  }

  receiptText.writeln('');
  receiptText.writeln('Importe utilizado: ${money(usedAmount)}');
  receiptText.writeln('Saldo disponible: ${money(remainingAmount)}');
  receiptText.writeln('Estado: $status');

  if (!context.mounted) {
    return;
  }

  final receiptImageKey = GlobalKey();

  showDialog(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Comprobante de uso'),
        content: SingleChildScrollView(
          child: RepaintBoundary(
            key: receiptImageKey,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F7F4),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFDCE9E0)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Gift Card: $code'),
                  const SizedBox(height: 8),
                  Text('Valor total: ${money(originalAmount)}'),
                  const SizedBox(height: 16),
                  const Text(
                    'Usos registrados',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),

                  ...usages.map((usage) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${money(usage['amountUsed'] ?? '0')}'
                        ' · ${usage['username'] ?? ''}'
                        ' · ${formatUsageDate(usage['usedAt'])}',
                      ),
                    );
                  }),

                  const SizedBox(height: 8),
                  Text(
                    'Importe utilizado: '
                    '${money(usedAmount)}',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Saldo disponible: '
                    '${money(remainingAmount)}',
                    style: const TextStyle(
                      color: greenColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Estado: $status'),
                ],
              ),
            ),
          ),
        ),
        actions: [
          if (status == 'Activa' || status == 'Parcialmente usada') ...[
            if (onBlock != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  onBlock!();
                },
                child: const Text('Bloquear'),
              ),
            if (onCancel != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  onCancel!();
                },
                child: const Text(
                  'Anular',
                  style: TextStyle(color: Colors.red),
                ),
              ),
          ],

          if (status == 'Bloqueada' && onReactivate != null)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                onReactivate!();
              },
              child: const Text('Reactivar'),
            ),

          OutlinedButton.icon(
            onPressed: () async {
              try {
                await WidgetsBinding.instance.endOfFrame;

                await Future<void>.delayed(const Duration(milliseconds: 100));

                if (!context.mounted) {
                  return;
                }

                final renderObject = receiptImageKey.currentContext
                    ?.findRenderObject();

                if (renderObject is! RenderRepaintBoundary) {
                  throw Exception('No se pudo preparar el comprobante.');
                }

                final image = await renderObject.toImage(pixelRatio: 2);

                final byteData = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );

                if (byteData == null) {
                  throw Exception(
                    'No se pudo convertir el comprobante en imagen.',
                  );
                }

                final imageBytes = byteData.buffer.asUint8List();

                final file = XFile.fromData(
                  imageBytes,
                  mimeType: 'image/png',
                  name: 'comprobante_${code}.png',
                );

                await SharePlus.instance.share(
                  ShareParams(title: 'Comprobante GiftCheck', files: [file]),
                );
              } catch (error) {
                if (!context.mounted) {
                  return;
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('No se pudo compartir el comprobante.'),
                  ),
                );
              }
            },
            icon: const Icon(Icons.share),
            label: const Text('Compartir'),
          ),

          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
            },
            child: const Text('Cerrar'),
          ),
        ],
      );
    },
  );
}

String formatUsageDate(Object? value) {
  DateTime? date;

  if (value is Timestamp) {
    date = value.toDate();
  } else if (value is DateTime) {
    date = value;
  } else if (value != null) {
    date = DateTime.tryParse(value.toString());
  }

  if (date == null) {
    return 'Fecha pendiente';
  }

  final localDate = date.toLocal();

  String twoDigits(int number) {
    return number.toString().padLeft(2, '0');
  }

  return '${twoDigits(localDate.day)}/'
      '${twoDigits(localDate.month)}/'
      '${localDate.year} — '
      '${twoDigits(localDate.hour)}:'
      '${twoDigits(localDate.minute)}';
}

Future<void> showGiftCheckErrorDialog({
  required BuildContext context,
  required String title,
  required String message,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: Colors.orange,
          size: 52,
        ),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(message, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
            },
            child: const Text('Cerrar'),
          ),
        ],
      );
    },
  );
}

Future<void> showGiftCheckSuccessDialog({
  required BuildContext context,
  required String title,
  required String message,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        icon: const Icon(
          Icons.check_circle_outline,
          color: greenColor,
          size: 52,
        ),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(message, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: greenColor),
            onPressed: () {
              Navigator.pop(dialogContext);
            },
            child: const Text('Aceptar'),
          ),
        ],
      );
    },
  );
}

class AppEntryPoint extends StatelessWidget {
  const AppEntryPoint({super.key});

  @override
  Widget build(BuildContext context) {
    final shareToken = Uri.base.queryParameters['ecard'];

    if (shareToken != null && shareToken.trim().isNotEmpty) {
      return PublicECardPage(shareToken: shareToken.trim());
    }

    return const AuthGate();
  }
}

class PublicECardPage extends StatelessWidget {
  const PublicECardPage({super.key, required this.shareToken});

  final String shareToken;

  Future<GiftCard?> _loadGiftCard() async {
    final data = await GiftCardService().findPublicECard(shareToken);

    if (data == null) {
      return null;
    }

    final expirationValue = data['expirationDate'];

    DateTime? expirationDate;

    if (expirationValue is Timestamp) {
      expirationDate = expirationValue.toDate();
    }

    return GiftCard(
      code: data['code'] as String? ?? '',
      amount: data['amount'] as String? ?? '',
      expirationDate: expirationDate,
      dedication: data['dedication'] as String? ?? '',
      senderName: data['senderName'] as String? ?? '',
      recipientName: data['recipientName'] as String? ?? '',
      status: data['status'] as String? ?? 'Activa',
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GiftCard?>(
      future: _loadGiftCard(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFFC69A4A)),
            ),
          );
        }

        final giftCard = snapshot.data;

        if (giftCard == null) {
          return const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Esta E-card no está disponible o el enlace no es válido.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        return ECardEnvelopePage(giftCard: giftCard);
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Widget _loadingScreen() {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: greenColor)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return _loadingScreen();
        }

        final user = authSnapshot.data;

        if (user == null) {
          return const LoginPage();
        }

        return FutureBuilder<AccountProfile?>(
          future: AccountService().getCurrentProfile(),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return _loadingScreen();
            }

            final profile = profileSnapshot.data;

            if (profile == null) {
              return const LoginPage();
            }

            if (profile.isAdministrator) {
              return AdminHomePage(displayName: profile.username);
            }

            return LocalHomePage(profile: profile);
          },
        );
      },
    );
  }
}

class GiftCheckApp extends StatelessWidget {
  const GiftCheckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GiftCheck',
      locale: const Locale('es', 'AR'),
      supportedLocales: const [Locale('es', 'AR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F7F4),
        colorScheme: ColorScheme.fromSeed(seedColor: greenColor),
      ),
      home: const AppEntryPoint(),
    );
  }
}

// ------------------------------------------------------------
// LOGIN
// ------------------------------------------------------------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();

  final AccountService _accountService = AccountService();

  bool _hidePassword = true;
  bool _loading = false;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _errorMessage(Object error) {
    final text = error.toString();

    if (text.startsWith('Exception: ')) {
      return text.replaceFirst('Exception: ', '');
    }

    return 'No se pudo completar la operación.';
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final profile = await _accountService.signIn(
        identifier: _identifierController.text,
        password: _passwordController.text,
      );

      if (!mounted) {
        return;
      }

      if (profile.isAdministrator) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => AdminHomePage(displayName: profile.username),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => LocalHomePage(profile: profile),
          ),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      await showGiftCheckErrorDialog(
        context: context,
        title: 'No se pudo iniciar sesión',
        message: _errorMessage(error),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _resetPassword() async {
    final identifier = _identifierController.text.trim();

    if (identifier.isEmpty) {
      await showGiftCheckErrorDialog(
        context: context,
        title: 'Falta completar un dato',
        message:
            'Ingresá tu usuario o email para poder recuperar la contraseña.',
      );
      return;
    }

    try {
      await _accountService.sendPasswordReset(identifier: identifier);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Te enviamos un email para recuperar la contraseña.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      await showGiftCheckErrorDialog(
        context: context,
        title: 'No se pudo recuperar la contraseña',
        message: _errorMessage(error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 30),

                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: greenColor,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: const Icon(
                        Icons.card_giftcard_rounded,
                        size: 48,
                        color: goldColor,
                      ),
                    ),

                    const SizedBox(height: 24),

                    const Text(
                      'GiftCheck',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: greenColor,
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'Gestión simple y segura de Gift Cards',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: grayTextColor, fontSize: 15),
                    ),

                    const SizedBox(height: 48),

                    const Text(
                      'Iniciar sesión',
                      style: TextStyle(
                        color: darkTextColor,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'Ingresá tu usuario o email para continuar.',
                      style: TextStyle(color: grayTextColor, fontSize: 14),
                    ),

                    const SizedBox(height: 28),

                    TextFormField(
                      controller: _identifierController,
                      decoration: appInputDecoration(
                        label: 'Usuario o email',
                        hint: 'Ingresá tu usuario o email',
                        prefixIcon: Icons.person_outline,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Ingresá tu usuario o email';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _passwordController,
                      obscureText: _hidePassword,
                      decoration: appInputDecoration(
                        label: 'Contraseña',
                        hint: 'Ingresá tu contraseña',
                        prefixIcon: Icons.lock_outline,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _hidePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () {
                            setState(() {
                              _hidePassword = !_hidePassword;
                            });
                          },
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Ingresá tu contraseña';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 12),

                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _resetPassword,
                        child: const Text(
                          '¿Olvidaste tu contraseña?',
                          style: TextStyle(
                            color: greenColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    SizedBox(
                      height: 56,
                      child: FilledButton(
                        onPressed: _loading ? null : _login,
                        style: FilledButton.styleFrom(
                          backgroundColor: greenColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Iniciar sesión',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    const Text(
                      'GiftCheck · Gestión interna de Gift Cards',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF8A958D), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CreateLocalAccountPage extends StatefulWidget {
  const CreateLocalAccountPage({super.key});

  @override
  State<CreateLocalAccountPage> createState() => _CreateLocalAccountPageState();
}

class _CreateLocalAccountPageState extends State<CreateLocalAccountPage> {
  final _formKey = GlobalKey<FormState>();

  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final AccountService _accountService = AccountService();

  static const String _selectedRole = 'local';

  bool _hidePassword = true;
  bool _hideConfirmPassword = true;
  bool _loading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();

    super.dispose();
  }

  String _errorMessage(Object error) {
    if (error is FirebaseAuthException) {
      if (error.code == 'email-already-in-use') {
        return 'Ese email ya está registrado.';
      }

      if (error.code == 'invalid-email') {
        return 'El email no es válido.';
      }

      if (error.code == 'weak-password') {
        return 'La contraseña es demasiado débil.';
      }

      if (error.code == 'operation-not-allowed') {
        return 'El registro con email y contraseña no está habilitado.';
      }

      return 'Error de autenticación: ${error.code}';
    }

    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'Firebase no permitió guardar los datos de la cuenta.';
      }

      return 'Error de Firebase: ${error.code}';
    }

    final text = error.toString();

    if (text.startsWith('Exception: ')) {
      return text.replaceFirst('Exception: ', '');
    }

    return 'No se pudo registrar la cuenta.';
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Las contraseñas no coinciden.')),
      );
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      await _accountService.registerAccount(
        username: _usernameController.text,
        email: _emailController.text,
        password: _passwordController.text,
        role: _selectedRole,
        localName: _usernameController.text,
      );

      if (!mounted) {
        return;
      }

      await showGiftCheckSuccessDialog(
        context: context,
        title: 'Cuenta creada',
        message:
            'La cuenta del local se creó correctamente. '
            'Por seguridad, tenés que iniciar sesión de nuevo con tu usuario.',
      );

      if (!mounted) {
        return;
      }

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      await showGiftCheckErrorDialog(
        context: context,
        title: 'No se pudo crear la cuenta',
        message: _errorMessage(error),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear cuenta de local'),
        backgroundColor: greenColor,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Nueva cuenta de local',
                  style: TextStyle(
                    color: darkTextColor,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Completá los datos del local.',
                  style: TextStyle(color: grayTextColor, fontSize: 15),
                ),

                const SizedBox(height: 28),

                TextFormField(
                  controller: _usernameController,
                  decoration: appInputDecoration(
                    label: 'Nombre del local',
                    hint: 'Ingresá el nombre del local',
                    prefixIcon: Icons.store_outlined,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingresá el nombre del local';
                    }

                    if (value.trim().length < 3) {
                      return 'Usá al menos 3 caracteres';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 18),

                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: appInputDecoration(
                    label: 'Email de recuperación',
                    hint: 'Ingresá un email',
                    prefixIcon: Icons.email_outlined,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingresá un email';
                    }

                    if (!value.contains('@')) {
                      return 'Ingresá un email válido';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 18),

                TextFormField(
                  controller: _passwordController,
                  obscureText: _hidePassword,
                  decoration: appInputDecoration(
                    label: 'Contraseña',
                    hint: 'Mínimo 6 caracteres',
                    prefixIcon: Icons.lock_outline,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _hidePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _hidePassword = !_hidePassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Ingresá una contraseña';
                    }

                    if (value.length < 6) {
                      return 'Usá al menos 6 caracteres';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 18),

                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _hideConfirmPassword,
                  decoration: appInputDecoration(
                    label: 'Repetir contraseña',
                    hint: 'Volvé a escribir la contraseña',
                    prefixIcon: Icons.lock_reset_outlined,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _hideConfirmPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _hideConfirmPassword = !_hideConfirmPassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Repetí la contraseña';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 28),

                SizedBox(
                  height: 56,
                  child: FilledButton(
                    onPressed: _loading ? null : _register,
                    style: FilledButton.styleFrom(
                      backgroundColor: greenColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Crear cuenta',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LocalHomePage extends StatelessWidget {
  const LocalHomePage({super.key, required this.profile});

  final AccountProfile profile;

  Future<void> _logout(BuildContext context) async {
    await AccountService().signOut();

    if (!context.mounted) {
      return;
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );
  }

  /// Runs [operation] behind a blocking progress indicator.
  ///
  /// Looking a card up needs a round trip to Firestore, which can take several
  /// seconds on a weak connection. Without this the app sits on the previous
  /// screen with no feedback at all, which reads as a freeze rather than a
  /// slow network.
  Future<T> _runWithProgress<T>(
    BuildContext context,
    Future<T> operation,
  ) async {
    final navigator = Navigator.of(context, rootNavigator: true);

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (_) => const PopScope(
          canPop: false,
          child: Center(child: CircularProgressIndicator(color: greenColor)),
        ),
      ),
    );

    try {
      return await operation;
    } finally {
      navigator.pop();
    }
  }

  Future<void> _showManualCodeDialog(
    BuildContext context, {
    String? initialCode,
  }) async {
    final codeController = TextEditingController(text: initialCode ?? '');

    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Consultar Gift Card'),
          content: TextField(
            controller: codeController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Código',
              hintText: 'Ejemplo: A01',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, codeController.text.trim());
              },
              child: const Text('Consultar'),
            ),
          ],
        );
      },
    );

    codeController.dispose();

    if (code == null || code.isEmpty || !context.mounted) {
      return;
    }

    try {
      final service = GiftCardService();
      final normalizedCode = code.trim().toUpperCase();

      // The card and its usages are independent reads keyed by the same code,
      // so they go out together instead of one after the other. On a slow
      // connection that is the difference between one round trip and two.
      final (giftCardData, usageRecords) = await _runWithProgress(
        context,
        (
          service.findGiftCardByCode(normalizedCode),
          service.loadGiftCardUsages(normalizedCode),
        ).wait,
      );

      if (!context.mounted) {
        return;
      }

      if (giftCardData == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No encontramos una Gift Card con ese código.'),
          ),
        );
        return;
      }

      final expirationValue = giftCardData['expirationDate'];

      final expirationDate = expirationValue is Timestamp
          ? expirationValue.toDate()
          : null;

      final expirationText = expirationDate == null
          ? 'Sin vencimiento'
          : formatDate(expirationDate);

      final displayStatus = effectiveGiftCardStatus(
        giftCardData['status']?.toString() ?? 'Activa',
        expirationDate,
      );

      showDialog(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text('Gift Card ${giftCardData['code'] ?? ''}'),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Importe original: '
                      '${money(giftCardData['amount'] ?? '')}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Importe utilizado: '
                      '${money(giftCardData['usedAmount'] ?? '0')}',
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE4F3EA),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Saldo disponible',
                            style: TextStyle(
                              color: greenColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            money(
                              giftCardData['remainingAmount'] ??
                                  giftCardData['amount'] ??
                                  '',
                            ),
                            style: const TextStyle(
                              color: greenColor,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),
                    Text('Estado: $displayStatus'),
                    if (displayStatus == 'Vencida') ...[
                      const SizedBox(height: 4),
                      Text(
                        'Venció el $expirationText.',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                    if (usageRecords.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Detalle de usos',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),

                      ...usageRecords.map((usage) {
                        final dateText = _formatUsageDate(usage['usedAt']);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${money(usage['amountUsed'] ?? '0')}'
                            ' · ${usage['username'] ?? ''}'
                            ' · $dateText',
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),

            actions: [
              if (displayStatus == 'Activa' ||
                  displayStatus == 'Parcialmente usada')
                FilledButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);

                    _showUsageDialog(context, giftCardData);
                  },
                  child: const Text('Registrar uso'),
                ),

              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }

      await showGiftCheckErrorDialog(
        context: context,
        title: 'No se pudo consultar la Gift Card',
        message:
            'No pudimos consultar la información de la Gift Card. '
            'Verificá el código y la conexión e intentá nuevamente.',
      );
    }
  }

  double _amountToNumber(Object? value) {
    final text = value?.toString() ?? '';

    final digitsOnly = text.replaceAll(RegExp(r'[^0-9]'), '');

    return double.tryParse(digitsOnly) ?? 0;
  }

  Future<void> _showUsageDialog(
    BuildContext context,
    Map<String, dynamic> giftCardData,
  ) async {
    final code = giftCardData['code']?.toString() ?? '';
    final originalAmount = _amountToNumber(giftCardData['amount']);

    final usages = await GiftCardService().loadGiftCardUsages(code);

    final usedAmount = usages.fold<double>(0, (total, usage) {
      return total + _amountToNumber(usage['amountUsed']);
    });

    final remainingAmount = originalAmount - usedAmount;

    if (!context.mounted) {
      return;
    }

    if (remainingAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta Gift Card ya no tiene saldo disponible.'),
        ),
      );
      return;
    }

    final rawExpirationValue = giftCardData['expirationDate'];
    final rawExpirationDate = rawExpirationValue is Timestamp
        ? rawExpirationValue.toDate()
        : null;

    if (isGiftCardExpired(rawExpirationDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esta Gift Card está vencida.')),
      );
      return;
    }

    final amountController = TextEditingController();

    final amountText = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Registrar uso de $code'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Importe original: '
                  '${money(originalAmount.toStringAsFixed(0))}',
                ),
                const SizedBox(height: 8),
                Text(
                  'Ya utilizado: '
                  '${money(usedAmount.toStringAsFixed(0))}',
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE4F3EA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Saldo disponible',
                        style: TextStyle(
                          color: greenColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        money(remainingAmount.toStringAsFixed(0)),
                        style: const TextStyle(
                          color: greenColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Importe a utilizar',
                    hintText:
                        'Ingresá un importe hasta '
                        '${money(remainingAmount.toStringAsFixed(0))}',
                    helperText: 'Debe ser menor o igual al saldo disponible.',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, amountController.text.trim());
              },
              child: const Text('Continuar'),
            ),
          ],
        );
      },
    );

    amountController.dispose();

    if (amountText == null || amountText.trim().isEmpty) {
      return;
    }

    final amountUsed = _amountToNumber(amountText);

    if (amountUsed <= 0 || amountUsed > remainingAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El importe ingresado no es válido o supera el saldo disponible.',
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Confirmar uso'),
          content: Text(
            '¿Confirmás utilizar '
            '${money(amountUsed.toStringAsFixed(0))} '
            'de la Gift Card $code?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      await GiftCardService().saveGiftCardUsage(
        giftCardCode: code,
        amountUsed: amountUsed.toStringAsFixed(0),
        username: profile.username,
        accountUid: profile.uid,
      );

      if (!context.mounted) {
        return;
      }

      final newUsedAmount = usedAmount + amountUsed;

      final newRemainingAmount = remainingAmount - amountUsed;

      final newStatus = newRemainingAmount <= 0
          ? 'Canjeada'
          : 'Parcialmente usada';

      await showUsageReceipt(
        context: context,
        code: code,
        username: profile.username,
        originalAmount: originalAmount.toStringAsFixed(0),
        usedAmount: newUsedAmount.toStringAsFixed(0),
        remainingAmount: newRemainingAmount.toStringAsFixed(0),
        status: newStatus,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      final errorText = error.toString();

      String message =
          'No se registró ningún uso. '
          'La Gift Card pudo haber cambiado mientras '
          'se confirmaba la operación. '
          'Consultá nuevamente el saldo e intentá otra vez.';

      if (errorText.contains('supera el saldo disponible')) {
        message =
            'El saldo disponible cambió o el importe ingresado '
            'supera el saldo actual de la Gift Card.';
      } else if (errorText.contains('No encontramos la Gift Card')) {
        message =
            'No encontramos una Gift Card con ese código. '
            'Verificá que esté escrito correctamente.';
      } else if (errorText.contains('no es válido')) {
        message =
            'El importe ingresado no es válido. '
            'Ingresá un monto mayor que cero.';
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            icon: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange,
              size: 52,
            ),
            title: const Text(
              'No se pudo registrar el uso',
              textAlign: TextAlign.center,
            ),
            content: Text(message, textAlign: TextAlign.center),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      );
    }
  }

  String _formatUsageDate(Object? value) {
    DateTime? date;

    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    } else if (value != null) {
      date = DateTime.tryParse(value.toString());
    }

    if (date == null) {
      return 'Fecha pendiente';
    }

    final localDate = date.toLocal();

    String twoDigits(int number) {
      return number.toString().padLeft(2, '0');
    }

    return '${twoDigits(localDate.day)}/'
        '${twoDigits(localDate.month)}/'
        '${localDate.year} — '
        '${twoDigits(localDate.hour)}:'
        '${twoDigits(localDate.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GiftCheck'),
        backgroundColor: greenColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),

              const Icon(
                Icons.storefront_outlined,
                color: greenColor,
                size: 64,
              ),

              const SizedBox(height: 20),

              Text(
                'Hola, ${profile.username}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: darkTextColor,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                profile.localName.isEmpty
                    ? 'Cuenta de local'
                    : profile.localName,
                textAlign: TextAlign.center,
                style: const TextStyle(color: grayTextColor, fontSize: 17),
              ),

              const SizedBox(height: 36),
              Card(
                elevation: 0,
                color: const Color(0xFFE4F3EA),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(20),
                  onTap: () async {
                    final scannedCode = await Navigator.push<String>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LocalQrScannerPage(),
                      ),
                    );

                    if (!context.mounted || scannedCode == null) {
                      return;
                    }

                    await _showManualCodeDialog(
                      context,
                      initialCode: scannedCode,
                    );
                  },

                  leading: const Icon(
                    Icons.qr_code_scanner,
                    color: greenColor,
                    size: 42,
                  ),
                  title: const Text(
                    'Escanear QR',
                    style: TextStyle(
                      color: darkTextColor,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: const Text(
                    'Escaneá el código de una Gift Card emitida.',
                  ),
                  trailing: const Icon(Icons.chevron_right, color: greenColor),
                ),
              ),

              const SizedBox(height: 16),

              Card(
                elevation: 0,
                color: Colors.white,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(20),
                  onTap: () {
                    _showManualCodeDialog(context);
                  },

                  leading: const Icon(
                    Icons.keyboard_alt_outlined,
                    color: greenColor,
                    size: 38,
                  ),
                  title: const Text(
                    'Ingresar código manualmente',
                    style: TextStyle(
                      color: darkTextColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: const Text(
                    'Usalo si el código QR no se puede leer.',
                  ),
                  trailing: const Icon(Icons.chevron_right, color: greenColor),
                ),
              ),

              const SizedBox(height: 16),

              Card(
                elevation: 0,
                color: Colors.white,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(20),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const UsageHistoryPage(),
                      ),
                    );
                  },

                  leading: const Icon(
                    Icons.history_rounded,
                    color: greenColor,
                    size: 38,
                  ),
                  title: const Text(
                    'Historial de usos',
                    style: TextStyle(
                      color: darkTextColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: const Text(
                    'Consultar Gift Cards utilizadas y sus movimientos.',
                  ),
                  trailing: const Icon(Icons.chevron_right, color: greenColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// HOME
// ------------------------------------------------------------

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key, required this.displayName});

  final String displayName;

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  final GiftCardService _giftCardService = GiftCardService();
  StreamSubscription<List<Map<String, dynamic>>>? _giftCardsSubscription;

  final List<GiftCard> _giftCards = [];

  @override
  void initState() {
    super.initState();
    _listenGiftCards();
  }

  void _listenGiftCards() {
    _giftCardsSubscription = _giftCardService.watchGiftCards().listen(
      (records) {
        final loadedGiftCards = records.map((data) {
          final expirationValue = data['expirationDate'];

          DateTime? expirationDate;

          if (expirationValue is DateTime) {
            expirationDate = expirationValue;
          }

          return GiftCard(
            code: data['code'] as String? ?? '',
            amount: data['amount'] as String? ?? '',
            expirationDate: expirationDate,
            dedication: data['dedication'] as String? ?? '',
            senderName: data['senderName'] as String? ?? '',
            recipientName: data['recipientName'] as String? ?? '',
            status: data['status'] as String? ?? 'Activa',
          );
        }).toList();

        if (!mounted) {
          return;
        }

        setState(() {
          _giftCards
            ..clear()
            ..addAll(loadedGiftCards);
        });
      },
      onError: (_) {
        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudieron actualizar las Gift Cards.'),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _giftCardsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _createGiftCard() async {
    late String reservedCode;

    try {
      reservedCode = await _giftCardService.reserveNextGiftCardCode();
    } catch (_) {
      if (!mounted) {
        return;
      }

      await showGiftCheckErrorDialog(
        context: context,
        title: 'No se pudo reservar un código nuevo',
        message:
            'No pudimos reservar un código nuevo. '
            'Verificá la conexión e intentá nuevamente.',
      );

      return;
    }

    final giftCard = await Navigator.push<GiftCard>(
      context,
      MaterialPageRoute(
        builder: (context) => CreateGiftCardPage(code: reservedCode),
      ),
    );

    if (giftCard == null || !mounted) {
      return;
    }

    try {
      final shareToken = await _giftCardService.saveGiftCard(
        code: giftCard.code,
        amount: giftCard.amount,
        expirationDate: giftCard.expirationDate,
        dedication: giftCard.dedication,
        senderName: giftCard.senderName,
        recipientName: giftCard.recipientName,
        status: giftCard.status,
      );

      if (!mounted) {
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GiftCardSuccessPage(
            giftCard: giftCard,
            shareToken: shareToken,
            onStatusChanged: (newStatus) {
              _updateGiftCardStatus(giftCard.code, newStatus);
            },
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      await showGiftCheckErrorDialog(
        context: context,
        title: 'No se pudo guardar la Gift Card',
        message:
            'No pudimos guardar la Gift Card en este momento.\n\n'
            'Detalle técnico: error',
      );
    }
  }

  Future<void> _updateGiftCardStatus(String code, String newStatus) async {
    final index = _giftCards.indexWhere((card) => card.code == code);

    if (index == -1) {
      return;
    }

    final previousGiftCard = _giftCards[index];

    setState(() {
      _giftCards[index] = _giftCards[index].copyWith(status: newStatus);
    });

    try {
      await _giftCardService.updateGiftCardStatus(
        code: code,
        status: newStatus,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _giftCards[index] = previousGiftCard;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar el cambio de estado.'),
        ),
      );
    }
  }

  Color _statusColor(String status) {
    if (status == 'Anulada') {
      return Colors.red;
    }

    if (status == 'Bloqueada') {
      return Colors.orange.shade800;
    }

    if (status == 'Vencida') {
      return const Color(0xFF374151);
    }

    return greenColor;
  }

  Color _statusBackgroundColor(String status) {
    if (status == 'Anulada') {
      return Colors.red.shade50;
    }

    if (status == 'Bloqueada') {
      return Colors.orange.shade50;
    }

    if (status == 'Vencida') {
      return const Color(0xFFE5E7EB);
    }

    return const Color(0xFFE4F3EA);
  }

  void _openGiftCardActions(GiftCard giftCard) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GiftCardSuccessPage(
          giftCard: giftCard,
          isExistingGiftCard: true,
          onStatusChanged: (newStatus) {
            _updateGiftCardStatus(giftCard.code, newStatus);
          },
        ),
      ),
    );
  }

  void _openAdminManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AdminManagementPage()),
    );
  }

  Future<void> _changeStatus(GiftCard giftCard, String newStatus) async {
    final title = newStatus == 'Bloqueada'
        ? 'Bloquear Gift Card'
        : newStatus == 'Anulada'
        ? 'Anular Gift Card'
        : 'Activar Gift Card';

    final message = newStatus == 'Bloqueada'
        ? 'La Gift Card no podrá utilizarse mientras esté bloqueada.'
        : newStatus == 'Anulada'
        ? 'La Gift Card quedará anulada y no podrá volver a utilizarse.'
        : 'La Gift Card volverá a estar activa.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: newStatus == 'Anulada'
                    ? Colors.red
                    : greenColor,
              ),
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    _updateGiftCardStatus(giftCard.code, newStatus);
  }

  Future<void> _showDetails(GiftCard giftCard) async {
    final usages = await _giftCardService.loadGiftCardUsages(giftCard.code);

    if (usages.isNotEmpty) {
      double parseAmount(Object? value) {
        final text = value?.toString() ?? '';

        final digitsOnly = text.replaceAll(RegExp(r'[^0-9]'), '');

        return double.tryParse(digitsOnly) ?? 0;
      }

      final originalAmount = parseAmount(giftCard.amount);

      final usedAmount = usages.fold<double>(0, (total, usage) {
        return total + parseAmount(usage['amountUsed']);
      });

      final remainingAmount = originalAmount - usedAmount;

      final status = remainingAmount <= 0
          ? 'Canjeada'
          : giftCard.status == 'Anulada'
          ? 'Anulada'
          : giftCard.status == 'Bloqueada'
          ? 'Bloqueada'
          : isGiftCardExpired(giftCard.expirationDate)
          ? 'Vencida'
          : 'Parcialmente usada';

      await showUsageReceipt(
        context: context,
        code: giftCard.code,
        username: usages.first['username']?.toString() ?? '',
        originalAmount: originalAmount.toStringAsFixed(0),
        usedAmount: usedAmount.toStringAsFixed(0),
        remainingAmount: remainingAmount.toStringAsFixed(0),
        status: status,
        onBlock: () {
          _changeStatus(giftCard, 'Bloqueada');
        },
        onCancel: () {
          _changeStatus(giftCard, 'Anulada');
        },
        onReactivate: () {
          _changeStatus(giftCard, 'Activa');
        },
      );

      return;
    }

    final expirationText = giftCard.expirationDate == null
        ? 'Sin vencimiento'
        : formatDate(giftCard.expirationDate!);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Detalle de Gift Card'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Código: ${giftCard.code}',
                style: const TextStyle(
                  color: greenColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text('Importe: ${money(giftCard.amount)}'),
              const SizedBox(height: 8),
              Text('Vence: $expirationText'),
              const SizedBox(height: 8),
              Text('Estado: ${giftCard.displayStatus}'),
            ],
          ),
          actions: [
            if (giftCard.status != 'Anulada')
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _openGiftCardActions(giftCard);
                },
                child: const Text('Compartir Gift Card'),
              ),

            if (giftCard.status == 'Activa')
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _changeStatus(giftCard, 'Bloqueada');
                },
                child: const Text('Bloquear'),
              ),

            if (giftCard.status == 'Bloqueada')
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _changeStatus(giftCard, 'Activa');
                },
                child: const Text('Activar'),
              ),

            if (giftCard.status != 'Anulada')
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _changeStatus(giftCard, 'Anulada');
                },
                child: const Text(
                  'Anular',
                  style: TextStyle(color: Colors.red),
                ),
              ),

            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cerrar sesión'),
          content: const Text('¿Querés cerrar la sesión?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Cerrar sesión'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );
    String _formatUsageDate(Object? value) {
      DateTime? date;

      if (value is Timestamp) {
        date = value.toDate();
      } else if (value is DateTime) {
        date = value;
      } else if (value != null) {
        date = DateTime.tryParse(value.toString());
      }

      if (date == null) {
        return 'Fecha pendiente';
      }

      final localDate = date.toLocal();

      String twoDigits(int number) {
        return number.toString().padLeft(2, '0');
      }

      return '${twoDigits(localDate.day)}/'
          '${twoDigits(localDate.month)}/'
          '${localDate.year} — '
          '${twoDigits(localDate.hour)}:'
          '${twoDigits(localDate.minute)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'GiftCheck',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: greenColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),

              Text(
                'Hola, ${widget.displayName}',
                style: const TextStyle(
                  color: darkTextColor,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                '¿Qué querés hacer hoy?',
                style: TextStyle(color: grayTextColor, fontSize: 16),
              ),

              const SizedBox(height: 32),

              Card(
                elevation: 0,
                color: const Color(0xFFE4F3EA),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.card_giftcard_rounded,
                        color: greenColor,
                        size: 42,
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Crear Gift Card',
                        style: TextStyle(
                          color: darkTextColor,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Generá una Gift Card para utilizar en cualquiera de los locales.',
                        style: TextStyle(color: grayTextColor, fontSize: 14),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: _createGiftCard,
                          icon: const Icon(Icons.add),
                          label: const Text('Crear Gift Card'),
                          style: FilledButton.styleFrom(
                            backgroundColor: greenColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ListTile(
                  onTap: _openAdminManagement,
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE4F3EA),
                    child: Icon(
                      Icons.admin_panel_settings_outlined,
                      color: greenColor,
                    ),
                  ),
                  title: const Text(
                    'Administrar locales y cuentas',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text('Gestioná locales, usuarios y accesos.'),
                  trailing: const Icon(Icons.chevron_right, color: greenColor),
                ),
              ),

              const SizedBox(height: 28),
              Card(
                elevation: 0,
                color: const Color(0xFFE4F3EA),
                child: ListTile(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => GiftCardHistoryPage(
                          giftCards: List<GiftCard>.from(_giftCards),
                        ),
                      ),
                    );
                  },
                  leading: const Icon(
                    Icons.history_rounded,
                    color: greenColor,
                    size: 32,
                  ),
                  title: const Text(
                    'Historial de Gift Cards',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Consultar todas las Gift Cards emitidas.',
                  ),
                  trailing: const Icon(Icons.chevron_right, color: greenColor),
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                'Gift Cards emitidas',
                style: TextStyle(
                  color: darkTextColor,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              if (_giftCards.isEmpty)
                Card(
                  elevation: 0,
                  color: Colors.white,
                  child: const Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(
                          Icons.card_giftcard_outlined,
                          size: 42,
                          color: Color(0xFF9AA89E),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Todavía no hay Gift Cards emitidas.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: grayTextColor),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ..._giftCards.map((giftCard) {
                  final expirationText = giftCard.expirationDate == null
                      ? 'Sin vencimiento'
                      : formatDate(giftCard.expirationDate!);

                  return Card(
                    elevation: 0,
                    color: Colors.white,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      onTap: () => _showDetails(giftCard),
                      leading: CircleAvatar(
                        backgroundColor: _statusBackgroundColor(
                          giftCard.displayStatus,
                        ),
                        child: Icon(
                          Icons.card_giftcard_rounded,
                          color: _statusColor(giftCard.displayStatus),
                        ),
                      ),
                      title: const Text(
                        'Gift Card',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'Código: ${giftCard.code}\n'
                        'Importe: ${money(giftCard.amount)}\n'
                        'Vence: $expirationText',
                      ),
                      isThreeLine: true,
                      trailing: Chip(
                        label: Text(giftCard.displayStatus),
                        backgroundColor: _statusBackgroundColor(
                          giftCard.displayStatus,
                        ),
                        labelStyle: TextStyle(
                          color: _statusColor(giftCard.displayStatus),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// CREAR GIFT CARD
// ------------------------------------------------------------
class ElCieloGiftCardVisual extends StatelessWidget {
  const ElCieloGiftCardVisual({super.key, required this.giftCard});

  final GiftCard giftCard;

  @override
  Widget build(BuildContext context) {
    final expirationText = giftCard.expirationDate == null
        ? ''
        : formatDate(giftCard.expirationDate!);

    final screen = MediaQuery.sizeOf(context);

    final availableWidth = screen.width - 32;
    final availableHeight = screen.height - 125;

    final cardSize = math.max(
      1.0,
      math.min(1000.0, math.min(availableWidth, availableHeight)),
    );

    return Center(
      child: SizedBox(
        width: cardSize,
        height: cardSize,
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: 1000,
            height: 1000,
            child: Container(
              padding: const EdgeInsets.all(55),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFEFD),

                border: Border.all(color: const Color(0xFFC69A4A), width: 4),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  const Positioned(
                    top: 0,
                    left: 0,
                    child: Icon(
                      Icons.favorite,
                      color: Color(0xFFC69A4A),
                      size: 28,
                    ),
                  ),
                  const Positioned(
                    top: 0,
                    right: 0,
                    child: Icon(
                      Icons.favorite,
                      color: Color(0xFFC69A4A),
                      size: 28,
                    ),
                  ),
                  const Positioned(
                    bottom: 0,
                    left: 0,
                    child: Icon(
                      Icons.favorite_border,
                      color: Color(0xFFC69A4A),
                      size: 28,
                    ),
                  ),
                  const Positioned(
                    bottom: 0,
                    right: 0,
                    child: Icon(
                      Icons.favorite_border,
                      color: Color(0xFFC69A4A),
                      size: 28,
                    ),
                  ),

                  Column(
                    children: [
                      // LOGOS SUPERIORES
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 90),
                        child: SizedBox(
                          width: double.infinity,
                          height: 78,
                          child: Image.asset(
                            'assets/el-cielo-logos.png',
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // TÍTULO PRINCIPAL
                      Text(
                        'GIFT CARD',
                        style: GoogleFonts.playfairDisplay(
                          color: const Color(0xFFC69A4A),
                          fontSize: 48,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 7,
                        ),
                      ),

                      const SizedBox(height: 5),

                      Text(
                        'VÁLIDA EN TODOS NUESTROS LOCALES',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.montserrat(
                          color: const Color(0xFF786B60),
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 3,
                        ),
                      ),

                      const SizedBox(height: 18),

                      // QR PROTEGIDO: FONDO BLANCO SIN DECORACIONES
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFFC9A45C),
                            width: 1,
                          ),
                        ),
                        child: QrImageView(
                          data: qrDataForGiftCard(giftCard),
                          size: 215,
                          backgroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                        ),
                      ),

                      const SizedBox(height: 22),

                      // DATOS DINÁMICOS
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (giftCard.recipientName.isNotEmpty) ...[
                                  Text(
                                    'PARA',
                                    style: GoogleFonts.montserrat(
                                      color: const Color(0xFFC69A4A),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    giftCard.recipientName,
                                    style: GoogleFonts.greatVibes(
                                      color: const Color(0xFF211A16),
                                      fontSize: 48,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                ],

                                if (giftCard.senderName.isNotEmpty) ...[
                                  Text(
                                    'DE PARTE DE',
                                    style: GoogleFonts.montserrat(
                                      color: const Color(0xFFC69A4A),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    giftCard.senderName,
                                    style: GoogleFonts.greatVibes(
                                      color: const Color(0xFF211A16),
                                      fontSize: 48,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                ],
                              ],
                            ),
                          ),

                          const SizedBox(width: 30),

                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'VALOR',
                                style: GoogleFonts.montserrat(
                                  color: const Color(0xFFC69A4A),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                money(giftCard.amount),
                                style: GoogleFonts.playfairDisplay(
                                  color: const Color(0xFF211A16),
                                  fontSize: 34,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // CÓDIGO Y VENCIMIENTO
                      Text(
                        'CÓDIGO',
                        style: GoogleFonts.montserrat(
                          color: const Color(0xFFC69A4A),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                        ),
                      ),

                      const SizedBox(height: 6),

                      const SizedBox(height: 6),

                      Text(
                        giftCard.code,
                        style: GoogleFonts.montserrat(
                          color: const Color(0xFF211A16),
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 3,
                        ),
                      ),

                      const SizedBox(height: 8),

                      _GiftCardInfoRow(
                        icon: Icons.favorite_border,
                        label: 'DE PARTE DE:',
                        value: giftCard.senderName,

                        maxLines: 2,
                      ),

                      if (giftCard.dedication.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _GiftCardInfoRow(
                          icon: Icons.favorite,
                          label: 'DEDICATORIA:',
                          value: giftCard.dedication,
                          maxLines: 2,
                        ),
                      ],

                      if (expirationText != null) ...[
                        const SizedBox(height: 10),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'VÁLIDA HASTA: $expirationText',
                            maxLines: 1,
                            softWrap: false,
                            style: GoogleFonts.montserrat(
                              color: const Color(0xFF786B60),
                              fontSize: 10,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ElCieloGiftCardShareVisual extends StatelessWidget {
  const ElCieloGiftCardShareVisual({super.key, required this.giftCard});

  final GiftCard giftCard;

  @override
  Widget build(BuildContext context) {
    final expirationText = giftCard.expirationDate == null
        ? ''
        : formatDate(giftCard.expirationDate!);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 1200.0;

        final cardWidth = math.min(1200.0, availableWidth);

        return SizedBox(
          width: cardWidth,
          height: cardWidth * 800 / 1200,
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(
              width: 1200,
              height: 800,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 42,
                  vertical: 24,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8EFE1),
                  border: Border.all(color: const Color(0xFFC69A4A), width: 5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 20,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Transform.translate(
                      offset: const Offset(0, -10),
                      child: SizedBox(
                        height: 58,
                        width: double.infinity,
                        child: Image.asset(
                          'assets/el-cielo-logos.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      'GIFT CARD',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.playfairDisplay(
                        color: const Color(0xFFC69A4A),
                        fontSize: 60,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 7,
                      ),
                    ),

                    const SizedBox(height: 2),

                    Text(
                      'VÁLIDA EN TODOS NUESTROS LOCALES',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.montserrat(
                        color: const Color(0xFF786B60),
                        fontSize: 14,
                        letterSpacing: 3,
                      ),
                    ),

                    const SizedBox(height: 12),

                    QrImageView(
                      data: qrDataForGiftCard(giftCard),
                      size: 190,
                      backgroundColor: Colors.white,
                    ),

                    const SizedBox(height: 5),

                    Text(
                      'CÓDIGO',
                      style: GoogleFonts.montserrat(
                        color: const Color(0xFFC69A4A),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2,
                      ),
                    ),

                    const SizedBox(height: 2),

                    Text(
                      giftCard.code,
                      style: GoogleFonts.montserrat(
                        color: const Color(0xFF211A16),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                      ),
                    ),

                    const SizedBox(height: 9),

                    Text(
                      'VALOR: ${money(giftCard.amount)}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.playfairDisplay(
                        color: const Color(0xFF211A16),
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Transform.translate(
                      offset: const Offset(0, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (giftCard.recipientName.isNotEmpty)
                              RichText(
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'PARA: ',
                                      style: GoogleFonts.montserrat(
                                        color: const Color(0xFFC69A4A),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                    TextSpan(
                                      text: giftCard.recipientName,
                                      style: GoogleFonts.greatVibes(
                                        color: const Color(0xFF211A16),
                                        fontSize: 46,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            const SizedBox(height: 8),
                            if (giftCard.recipientName.isNotEmpty)
                              RichText(
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'PARA: ',
                                      style: GoogleFonts.montserrat(
                                        color: const Color(0xFFC69A4A),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                    TextSpan(
                                      text: giftCard.recipientName,
                                      style: GoogleFonts.greatVibes(
                                        color: const Color(0xFF211A16),
                                        fontSize: 46,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            const SizedBox(height: 8),
                            if (giftCard.senderName.isNotEmpty)
                              RichText(
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'DE PARTE DE: ',
                                      style: GoogleFonts.montserrat(
                                        color: const Color(0xFFC69A4A),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                    TextSpan(
                                      text: giftCard.senderName,
                                      style: GoogleFonts.greatVibes(
                                        color: const Color(0xFF211A16),
                                        fontSize: 46,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    if (expirationText.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(
                        'VÁLIDA HASTA: $expirationText',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.montserrat(
                          color: const Color(0xFF786B60),
                          fontSize: 10,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ECardEnvelopePage extends StatefulWidget {
  const ECardEnvelopePage({
    super.key,
    this.giftCard,
    this.code = 'A000001',
    this.amount = '130000',
    this.dedication = 'Una sorpresa para vos',
    this.expirationText = '',
  });

  final String code;
  final String amount;
  final String dedication;
  final String expirationText;
  final GiftCard? giftCard;

  @override
  State<ECardEnvelopePage> createState() => _ECardEnvelopePageState();
}

class _ECardEnvelopePageState extends State<ECardEnvelopePage> {
  bool _opened = false;
  final GlobalKey _eCardImageKey = GlobalKey();
  bool _isSharing = false;

  Future<Uint8List> _createECardImage() async {
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 250));

    final renderObject = _eCardImageKey.currentContext?.findRenderObject();

    if (renderObject is! RenderRepaintBoundary) {
      throw Exception('No se pudo preparar la E-card.');
    }

    final image = await renderObject.toImage(pixelRatio: 3);

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) {
      throw Exception('No se pudo convertir la E-card en imagen.');
    }

    return byteData.buffer.asUint8List();
  }

  Future<void> _shareECard() async {
    if (_isSharing) {
      return;
    }

    setState(() {
      _isSharing = true;
    });

    try {
      final imageBytes = await _createECardImage();

      final file = XFile.fromData(
        imageBytes,
        mimeType: 'image/png',
        name: 'ecard_el_cielo_${widget.code}.png',
      );

      await SharePlus.instance.share(
        ShareParams(title: 'E-card El Cielo', files: [file]),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo preparar la E-card para compartir.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSharing = false;
        });
      }
    }
  }

  Widget _buildEnvelope() {
    return GestureDetector(
      key: const ValueKey('envelope'),
      onTap: () {
        setState(() {
          _opened = true;
        });
      },
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/envelope.png',
              fit: BoxFit.contain,
              width: double.infinity,
              height: 360,
            ),
            const SizedBox(height: 16),
            const Text(
              'Tenés un regalo',
              style: TextStyle(
                color: darkTextColor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tocá el sobre para abrirlo',
              style: TextStyle(
                color: greenColor,
                fontSize: 15,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGiftCard() {
    return SingleChildScrollView(
      key: const ValueKey('gift-card'),
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          RepaintBoundary(
            key: _eCardImageKey,
            child: GiftCardVisual(
              giftCard:
                  widget.giftCard ??
                  GiftCard(
                    code: widget.code,
                    amount: widget.amount,
                    expirationDate: null,
                    dedication: widget.dedication,
                    status: 'Activa',
                  ),
            ),
          ),

          const SizedBox(height: 18),

          const Text(
            'Presentá este código QR en el local '
            'para validar tu Gift Card.',
            textAlign: TextAlign.center,
            style: TextStyle(color: grayTextColor, fontSize: 13, height: 1.4),
          ),

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isSharing ? null : _shareECard,
              icon: const Icon(Icons.share_outlined),
              label: Text(
                _isSharing ? 'Preparando E-card...' : 'Compartir E-card',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC69A4A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),

          const SizedBox(height: 12),

          OutlinedButton(
            onPressed: () {
              setState(() {
                _opened = false;
              });
            },
            child: const Text('Volver a ver el sobre'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gift Card'),
        backgroundColor: greenColor,
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFF7F3EA),
      body: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 650),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final slideAnimation = Tween<Offset>(
              begin: const Offset(0, 0.15),
              end: Offset.zero,
            ).animate(animation);

            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: slideAnimation, child: child),
            );
          },
          child: _opened ? _buildGiftCard() : _buildEnvelope(),
        ),
      ),
    );
  }
}

class CreateGiftCardPage extends StatefulWidget {
  const CreateGiftCardPage({super.key, required this.code});

  final String code;

  @override
  State<CreateGiftCardPage> createState() => _CreateGiftCardPageState();
}

class _CreateGiftCardPageState extends State<CreateGiftCardPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _dedicationController = TextEditingController();
  final _senderController = TextEditingController();
  final _recipientController = TextEditingController();
  DateTime? _expirationDate;

  @override
  void dispose() {
    _amountController.dispose();
    _senderController.dispose();
    _recipientController.dispose();
    _dedicationController.dispose();
    super.dispose();
  }

  Future<bool> _handleBack() async {
    final hasData =
        _amountController.text.trim().isNotEmpty ||
        _dedicationController.text.trim().isNotEmpty ||
        _expirationDate != null;

    if (!hasData) {
      return true;
    }

    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Salir sin guardar'),
          content: const Text(
            '¿Querés volver sin guardar los datos ingresados?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Continuar editando'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Salir'),
            ),
          ],
        );
      },
    );

    return leave == true;
  }

  DateTime _validDateForMonth(
    DateTime date,
    int year,
    int month,
    DateTime firstDate,
    DateTime lastDate,
  ) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final day = date.day > daysInMonth ? daysInMonth : date.day;

    var result = DateTime(year, month, day);

    if (result.isBefore(firstDate)) {
      result = firstDate;
    }

    if (result.isAfter(lastDate)) {
      result = lastDate;
    }

    return result;
  }

  Future<DateTime?> _pickExpirationDate() async {
    final now = DateTime.now();

    // ============================================================
    // RANGO DE FECHAS
    // ============================================================

    // Permitimos mostrar desde el primer día del año actual.
    final firstDate = DateTime(now.year, 1, 1);

    // Año máximo permitido.
    const int lastYear = 2100;

    // Última fecha disponible.
    final lastDate = DateTime(lastYear, 12, 31);

    // ============================================================
    // FECHA INICIAL
    // ============================================================

    DateTime selectedDate = _expirationDate ?? now;

    // Si existe una fecha guardada anterior a hoy,
    // comenzamos desde hoy.
    if (selectedDate.isBefore(now)) {
      selectedDate = now;
    }

    // Si por algún motivo la fecha guardada supera 2100,
    // usamos la última fecha permitida.
    if (selectedDate.isAfter(lastDate)) {
      selectedDate = lastDate;
    }

    DateTime displayedMonth = DateTime(
      selectedDate.year,
      selectedDate.month,
      1,
    );

    const months = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];

    // ============================================================
    // DIALOG
    // ============================================================

    return showDialog<DateTime>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final screenWidth = MediaQuery.sizeOf(context).width;

            final dialogWidth = math.min(360.0, screenWidth - 48);

            return AlertDialog(
              title: const Text('Elegir vencimiento'),

              content: SizedBox(
                width: dialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ==================================================
                    // SELECTORES DE MES Y AÑO
                    // ==================================================
                    Row(
                      children: [
                        // =================================================
                        // MES
                        // =================================================
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            isExpanded: true,
                            value: displayedMonth.month,

                            decoration: const InputDecoration(
                              labelText: 'Mes',
                              border: OutlineInputBorder(),
                            ),

                            items: List.generate(12, (index) {
                              return DropdownMenuItem<int>(
                                value: index + 1,
                                child: Text(
                                  months[index],
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }),

                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }

                              final newYear = displayedMonth.year;
                              final newMonth = value;

                              final newMonthDate = DateTime(
                                newYear,
                                newMonth,
                                1,
                              );

                              final currentMonthDate = DateTime(
                                now.year,
                                now.month,
                                1,
                              );

                              final isCurrentMonth =
                                  newYear == now.year && newMonth == now.month;

                              final isFutureMonth = newMonthDate.isAfter(
                                currentMonthDate,
                              );

                              // Actualizamos el mes mostrado.
                              displayedMonth = newMonthDate;

                              // ==========================================
                              // MES FUTURO
                              // ==========================================

                              if (isFutureMonth) {
                                // Siempre comenzamos en el día 1.
                                selectedDate = DateTime(newYear, newMonth, 1);
                              }
                              // ==========================================
                              // MES ACTUAL
                              // ==========================================
                              else if (isCurrentMonth) {
                                // Volvemos a hoy.
                                selectedDate = DateTime(
                                  now.year,
                                  now.month,
                                  now.day,
                                );
                              }
                              // ==========================================
                              // MES PASADO
                              // ==========================================
                              else {
                                // Se mantiene bloqueado.
                                selectedDate = DateTime(newYear, newMonth, 1);
                              }

                              setDialogState(() {});
                            },
                          ),
                        ),

                        const SizedBox(width: 8),

                        // =================================================
                        // AÑO
                        // =================================================
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            isExpanded: true,
                            value: displayedMonth.year,

                            decoration: const InputDecoration(
                              labelText: 'Año',
                              border: OutlineInputBorder(),
                            ),

                            // Desde el año actual hasta 2100.
                            items: List.generate(lastYear - now.year + 1, (
                              index,
                            ) {
                              final year = now.year + index;

                              return DropdownMenuItem<int>(
                                value: year,
                                child: Text(year.toString()),
                              );
                            }),

                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }

                              final newYear = value;
                              final newMonth = displayedMonth.month;

                              final newMonthDate = DateTime(
                                newYear,
                                newMonth,
                                1,
                              );

                              final currentMonthDate = DateTime(
                                now.year,
                                now.month,
                                1,
                              );

                              displayedMonth = newMonthDate;

                              // ==========================================
                              // AÑO FUTURO
                              // ==========================================

                              if (newMonthDate.isAfter(currentMonthDate)) {
                                // Año futuro:
                                // comenzamos siempre en el día 1.
                                selectedDate = DateTime(newYear, newMonth, 1);
                              }
                              // ==========================================
                              // AÑO ACTUAL
                              // ==========================================
                              else if (newYear == now.year) {
                                if (newMonth == now.month) {
                                  // Mes actual:
                                  // seleccionamos hoy.
                                  selectedDate = DateTime(
                                    now.year,
                                    now.month,
                                    now.day,
                                  );
                                } else if (newMonth > now.month) {
                                  // Mes futuro dentro del año actual:
                                  // comenzamos en el día 1.
                                  selectedDate = DateTime(newYear, newMonth, 1);
                                } else {
                                  // Mes pasado:
                                  // queda bloqueado.
                                  selectedDate = DateTime(newYear, newMonth, 1);
                                }
                              }

                              setDialogState(() {});
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // ==================================================
                    // CALENDARIO
                    // ==================================================
                    CalendarDatePicker(
                      key: ValueKey(
                        '${displayedMonth.year}-${displayedMonth.month}',
                      ),

                      initialDate: selectedDate,

                      // Primer día visible permitido.
                      firstDate: firstDate,

                      // Último día permitido: 31/12/2100.
                      lastDate: lastDate,

                      // Marca el día de hoy.
                      currentDate: now,

                      // ==================================================
                      // DÍAS SELECCIONABLES
                      // ==================================================
                      selectableDayPredicate: (date) {
                        // ----------------------------------------------
                        // MES ACTUAL
                        // ----------------------------------------------

                        if (date.year == now.year && date.month == now.month) {
                          return !date.isBefore(
                            DateTime(now.year, now.month, now.day),
                          );
                        }

                        // ----------------------------------------------
                        // MESES FUTUROS
                        // ----------------------------------------------

                        if (date.isAfter(
                          DateTime(now.year, now.month + 1, 0),
                        )) {
                          return true;
                        }

                        // ----------------------------------------------
                        // MESES PASADOS
                        // ----------------------------------------------

                        return false;
                      },

                      // ==================================================
                      // CUANDO EL USUARIO SELECCIONA UNA FECHA
                      // ==================================================
                      onDateChanged: (date) {
                        // Seguridad:
                        // nunca permitimos una fecha anterior a hoy.
                        if (date.isBefore(
                          DateTime(now.year, now.month, now.day),
                        )) {
                          return;
                        }

                        // Seguridad:
                        // nunca permitimos superar 2100.
                        if (date.isAfter(lastDate)) {
                          return;
                        }

                        selectedDate = date;

                        displayedMonth = DateTime(date.year, date.month, 1);

                        setDialogState(() {});
                      },
                    ),
                  ],
                ),
              ),

              // ==========================================================
              // BOTONES
              // ==========================================================
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancelar'),
                ),

                FilledButton(
                  onPressed: () {
                    Navigator.pop(dialogContext, selectedDate);
                  },
                  child: const Text('Elegir fecha'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _selectExpirationDate() async {
    final selectedDate = await _pickExpirationDate();

    if (selectedDate == null || !mounted) {
      return;
    }

    setState(() {
      _expirationDate = selectedDate;
    });
  }

  Future<void> _showPreview() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final giftCard = GiftCard(
      code: widget.code,
      amount: _amountController.text.trim(),
      expirationDate: _expirationDate,
      dedication: _dedicationController.text.trim(),
      senderName: _senderController.text.trim(),
      recipientName: _recipientController.text.trim(),
      status: 'Activa',
    );

    final confirmed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => GiftCardPreviewPage(giftCard: giftCard),
      ),
    );

    if (confirmed == true && mounted) {
      Navigator.pop(context, giftCard);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleBack,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Crear Gift Card'),
          backgroundColor: greenColor,
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Nueva Gift Card',
                    style: TextStyle(
                      color: darkTextColor,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Completá los datos para generar una nueva tarjeta.',
                    style: TextStyle(color: grayTextColor, fontSize: 15),
                  ),

                  const SizedBox(height: 32),

                  TextFormField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: appInputDecoration(
                      label: 'Importe',
                      hint: 'Ejemplo: 50000',
                      prefixIcon: Icons.payments_outlined,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Ingresá un importe';
                      }

                      return null;
                    },
                  ),

                  const SizedBox(height: 18),

                  InkWell(
                    onTap: _selectExpirationDate,
                    borderRadius: BorderRadius.circular(16),
                    child: InputDecorator(
                      decoration: appInputDecoration(
                        label: 'Fecha de vencimiento opcional',
                        prefixIcon: Icons.calendar_month_outlined,
                      ),
                      child: Text(
                        _expirationDate == null
                            ? 'Sin vencimiento'
                            : formatDate(_expirationDate!),
                        style: TextStyle(
                          color: _expirationDate == null
                              ? grayTextColor
                              : darkTextColor,
                        ),
                      ),
                    ),
                  ),

                  TextFormField(
                    controller: _recipientController,
                    decoration: appInputDecoration(
                      label: 'Para',
                      hint: 'Ejemplo: María',
                      prefixIcon: Icons.person_outline,
                    ),
                  ),

                  const SizedBox(height: 18),

                  TextFormField(
                    controller: _senderController,
                    decoration: appInputDecoration(
                      label: 'De parte de',
                      hint: 'Ejemplo: Marian',
                      prefixIcon: Icons.person_outline,
                    ),
                  ),

                  const SizedBox(height: 18),

                  TextFormField(
                    controller: _dedicationController,
                    maxLines: 4,
                    decoration: appInputDecoration(
                      label: 'Frase dedicatoria opcional',
                      hint: 'Ejemplo: Que disfrutes mucho tu regalo',
                      prefixIcon: Icons.favorite_border,
                    ),
                  ),

                  const SizedBox(height: 28),

                  SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: _showPreview,
                      icon: const Icon(Icons.card_giftcard_outlined),
                      label: const Text(
                        'Crear Gift Card',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: greenColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// VISTA PREVIA
// ------------------------------------------------------------

class GiftCardPreviewPage extends StatelessWidget {
  const GiftCardPreviewPage({super.key, required this.giftCard});

  final GiftCard giftCard;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vista previa'),
        backgroundColor: greenColor,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Revisá los datos',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: darkTextColor,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Si está todo correcto, confirmá la Gift Card.',
                textAlign: TextAlign.center,
                style: TextStyle(color: grayTextColor, fontSize: 14),
              ),

              const SizedBox(height: 28),

              GiftCardVisual(giftCard: giftCard),

              const SizedBox(height: 28),

              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context, true);
                  },
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text(
                    'Confirmar Gift Card',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: greenColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              OutlinedButton(
                onPressed: () {
                  Navigator.pop(context, false);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: greenColor,
                  side: const BorderSide(color: greenColor),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Volver a editar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// DISEÑO DE LA IMAGEN
// ------------------------------------------------------------

class GiftCardVisual extends StatelessWidget {
  const GiftCardVisual({super.key, required this.giftCard});

  final GiftCard giftCard;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(535.0, constraints.maxWidth);
        return Center(
          child: SizedBox(
            width: width,
            height: width * 785 / 535,
            child: FittedBox(
              fit: BoxFit.contain,
              child: Container(
                width: 535,
                height: 785,
                padding: const EdgeInsets.fromLTRB(50, 26, 50, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black, width: 3),
                  boxShadow: const [
                    BoxShadow(color: Color(0x22000000), blurRadius: 20),
                  ],
                ),
                child: Column(
                  children: [
                    SizedBox(
                      width: 245,
                      height: 30,
                      child: Image.asset(
                        'assets/el-cielo-logos.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 18),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('GIFT', style: GoogleFonts.montserrat(
                            color: Colors.black,
                            fontSize: 68,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.5,
                          )),
                          const SizedBox(width: 6),
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              Text('CARD', style: GoogleFonts.montserrat(
                                foreground: Paint()
                                  ..style = PaintingStyle.stroke
                                  ..strokeWidth = 2
                                  ..color = Colors.black,
                                fontSize: 68,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -1.5,
                              )),
                              Text('CARD', style: GoogleFonts.montserrat(
                                color: Colors.white,
                                fontSize: 68,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -1.5,
                              )),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 42),
                    SizedBox(
                      width: 250,
                      height: 264,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 190,
                            height: 190,
                            color: const Color(0xFFF5F6F7),
                            padding: const EdgeInsets.all(6),
                            child: QrImageView(
                              data: qrDataForGiftCard(giftCard),
                              size: 178,
                              backgroundColor: Colors.white,
                              padding: const EdgeInsets.all(7),
                            ),
                          ),
                          const Positioned(top: 0, left: 0,
                            child: _QrCorner()),
                          const Positioned(top: 0, right: 0,
                            child: _QrCorner(flipX: true)),
                          const Positioned(bottom: 0, left: 0,
                            child: _QrCorner(flipY: true)),
                          const Positioned(bottom: 0, right: 0,
                            child: _QrCorner(flipX: true, flipY: true)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    _GiftCardLine(label: 'PARA:', value: giftCard.recipientName),
                    const SizedBox(height: 14),
                    _GiftCardLine(label: 'DE:', value: giftCard.senderName),
                    const SizedBox(height: 20),
                    const Spacer(),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          const Text('\$', style: TextStyle(
                            color: Colors.black,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                          )),
                          const SizedBox(width: 10),
                          Text(
                            money(giftCard.amount).replaceFirst('\$', '').trim(),
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 23,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'CÓDIGO ${giftCard.code}',
                      style: GoogleFonts.montserrat(
                        color: Colors.black,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _QrCorner extends StatelessWidget {
  const _QrCorner({this.flipX = false, this.flipY = false});
  final bool flipX;
  final bool flipY;

  @override
  Widget build(BuildContext context) => Transform.flip(
    flipX: flipX,
    flipY: flipY,
    child: Container(
      width: 92,
      height: 100,
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: Colors.black, width: 14),
          top: BorderSide(color: Colors.black, width: 14),
        ),
      ),
    ),
  );
}

class _GiftCardLine extends StatelessWidget {
  const _GiftCardLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 250,
    child: Column(children: [
      Text(label, style: const TextStyle(fontSize: 16,
          fontWeight: FontWeight.w800)),
      SizedBox(
        height: 30,
        child: Center(child: Text(value, maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 17))),
      ),
      const Divider(color: Colors.black, thickness: 1),
    ]),
  );
}

// ============================================================================
// FILA PARA / DE PARTE DE
// ============================================================================

class _GiftCardInfoRow extends StatelessWidget {
  const _GiftCardInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.maxLines = 2,
  });

  final IconData icon;
  final String label;
  final String value;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: const Color(0xFFC9A45C), size: 14),

        const SizedBox(width: 7),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.1,
                    ),
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child: Text(
                      value,
                      maxLines: maxLines,
                      overflow: TextOverflow.ellipsis,
                      style: giftCardValueTextStyle(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// TEXTO DECORATIVO DEL FONDO
// ============================================================================

class _WatermarkText extends StatelessWidget {
  const _WatermarkText({
    required this.text,
    required this.fontSize,
    this.textAlign = TextAlign.left,
  });

  final String text;
  final double fontSize;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: textAlign,
      style: GoogleFonts.greatVibes(
        color: const Color(0xFFC69A5C),
        fontSize: fontSize,
        fontWeight: FontWeight.w400,
        height: 1.05,
      ),
    );
  }
}

// ============================================================================
// CORAZÓN DECORATIVO
// ============================================================================

class _WatermarkHeart extends StatelessWidget {
  const _WatermarkHeart({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.favorite_border,
      size: size,
      color: const Color(0xFFC9A45C),
    );
  }
}

// ============================================================================
// DETALLE DE ESQUINA
// ============================================================================

class _CornerDecoration extends StatelessWidget {
  const _CornerDecoration({this.flipX = false, this.flipY = false});

  final bool flipX;
  final bool flipY;

  @override
  Widget build(BuildContext context) {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..scale(flipX ? -1.0 : 1.0, flipY ? -1.0 : 1.0),
      child: SizedBox(
        width: 28,
        height: 28,
        child: CustomPaint(painter: _CornerPainter()),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFC9A45C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final path = Path();

    path.moveTo(0, size.height);
    path.lineTo(0, 8);
    path.quadraticBezierTo(0, 0, 8, 0);

    path.lineTo(size.width, 0);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

// ------------------------------------------------------------
// PANTALLA DESPUÉS DE CONFIRMAR
// ------------------------------------------------------------

class GiftCardSuccessPage extends StatefulWidget {
  const GiftCardSuccessPage({
    super.key,
    required this.giftCard,
    required this.onStatusChanged,
    this.isExistingGiftCard = false,
    this.shareToken,
  });

  final GiftCard giftCard;
  final void Function(String newStatus) onStatusChanged;
  final bool isExistingGiftCard;
  final String? shareToken;

  @override
  State<GiftCardSuccessPage> createState() => _GiftCardSuccessPageState();
}

class _GiftCardSuccessPageState extends State<GiftCardSuccessPage> {
  final GlobalKey _giftCardImageKey = GlobalKey();

  late String _currentStatus;
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.giftCard.status;
  }

  Future<Uint8List> _createGiftCardImage() async {
    await WidgetsBinding.instance.endOfFrame;

    await Future<void>.delayed(const Duration(milliseconds: 250));

    final renderObject = _giftCardImageKey.currentContext?.findRenderObject();

    if (renderObject is! RenderRepaintBoundary) {
      throw Exception('No se pudo preparar la imagen de la Gift Card.');
    }

    final image = await renderObject.toImage(pixelRatio: 3);

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) {
      throw Exception('No se pudo convertir la Gift Card en imagen.');
    }

    return byteData.buffer.asUint8List();
  }

  Future<void> _shareGiftCard() async {
    if (_isSharing) {
      return;
    }

    setState(() {
      _isSharing = true;
    });

    try {
      final imageBytes = await _createGiftCardImage();

      final file = XFile.fromData(
        imageBytes,
        mimeType: 'image/png',
        name: 'gift_card_${widget.giftCard.code}.png',
      );

      await SharePlus.instance.share(
        ShareParams(title: 'Gift Card', files: [file]),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir el menú para compartir la imagen.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSharing = false;
        });
      }
    }
  }

  Future<void> _sharePublicECard() async {
    final token = widget.shareToken;

    if (token == null || token.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta Gift Card todavía no tiene enlace público.'),
        ),
      );

      return;
    }

    final publicLink = Uri.base
        .replace(queryParameters: {'ecard': token})
        .toString();

    await SharePlus.instance.share(
      ShareParams(
        title: 'E-card El Cielo',
        text:
            'Tenés un regalo especial de El Cielo. '
            'Abrí el sobre para descubrirlo:\n\n'
            '$publicLink',
      ),
    );
  }

  Future<void> _changeStatus(String newStatus) async {
    final title = newStatus == 'Bloqueada'
        ? 'Bloquear Gift Card'
        : newStatus == 'Anulada'
        ? 'Anular Gift Card'
        : 'Activar Gift Card';

    final message = newStatus == 'Bloqueada'
        ? 'La Gift Card no podrá utilizarse mientras esté bloqueada.'
        : newStatus == 'Anulada'
        ? 'La Gift Card quedará anulada y no podrá volver a utilizarse.'
        : 'La Gift Card volverá a estar activa.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: newStatus == 'Anulada'
                    ? Colors.red
                    : greenColor,
              ),
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _currentStatus = newStatus;
    });

    widget.onStatusChanged(newStatus);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newStatus == 'Bloqueada'
              ? 'Gift Card bloqueada.'
              : newStatus == 'Anulada'
              ? 'Gift Card anulada.'
              : 'Gift Card activada nuevamente.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isExistingGiftCard
              ? 'Detalle de Gift Card'
              : 'Gift Card creada',
        ),
        backgroundColor: greenColor,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.isExistingGiftCard) ...[
                const Icon(
                  Icons.check_circle_rounded,
                  color: greenColor,
                  size: 72,
                ),

                const SizedBox(height: 16),

                const Text(
                  'Gift Card guardada correctamente',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: darkTextColor,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 28),
              ],

              RepaintBoundary(
                key: _giftCardImageKey,
                child: GiftCardVisual(giftCard: widget.giftCard),
              ),

              const SizedBox(height: 24),

              if (_currentStatus != 'Anulada')
                SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: _isSharing ? null : _shareGiftCard,
                    icon: const Icon(Icons.share_outlined),
                    label: Text(
                      _isSharing
                          ? 'Preparando imagen...'
                          : 'Compartir Gift Card',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: greenColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Esta Gift Card está anulada y no se puede compartir.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(height: 12),

              const SizedBox(height: 24),

              const Divider(),

              const SizedBox(height: 18),

              if (_currentStatus == 'Activa') ...[
                OutlinedButton.icon(
                  onPressed: () => _changeStatus('Bloqueada'),
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Bloquear Gift Card'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade800,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),

                const SizedBox(height: 6),

                OutlinedButton.icon(
                  onPressed: () => _changeStatus('Anulada'),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Anular Gift Card'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ],

              if (_currentStatus == 'Bloqueada') ...[
                OutlinedButton.icon(
                  onPressed: () => _changeStatus('Activa'),
                  icon: const Icon(Icons.lock_open_outlined),
                  label: const Text('Activar nuevamente'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: greenColor,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),

                const SizedBox(height: 10),

                OutlinedButton.icon(
                  onPressed: () => _changeStatus('Anulada'),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Anular Gift Card'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ],

              if (_currentStatus == 'Anulada')
                const Text(
                  'Esta Gift Card está anulada.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),

              const SizedBox(height: 18),

              OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: greenColor,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  side: const BorderSide(color: greenColor),
                ),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminManagementPage extends StatelessWidget {
  const AdminManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración'),
        backgroundColor: greenColor,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Administrar locales y cuentas',
              style: TextStyle(
                color: darkTextColor,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Desde acá podés administrar la estructura de la empresa.',
              style: TextStyle(color: grayTextColor, fontSize: 15),
            ),

            const SizedBox(height: 28),

            Card(
              elevation: 0,
              color: Colors.white,
              child: ListTile(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AccountManagementPage(),
                    ),
                  );
                },

                leading: const Icon(
                  Icons.manage_accounts_outlined,
                  color: greenColor,
                  size: 32,
                ),
                title: const Text(
                  'Administrar cuentas',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'Gestionar administradoras y cuentas de locales.',
                ),
                trailing: const Icon(Icons.chevron_right, color: greenColor),
              ),
            ),

            const SizedBox(height: 12),

            Card(
              elevation: 0,
              color: Colors.white,
              child: ListTile(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CreateLocalAccountPage(),
                    ),
                  );
                },

                leading: const Icon(
                  Icons.person_add_alt_1_outlined,
                  color: greenColor,
                  size: 32,
                ),
                title: const Text(
                  'Crear cuenta',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text('Registrar la cuenta de un local nuevo.'),
                trailing: const Icon(Icons.chevron_right, color: greenColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LocalManagementPage extends StatefulWidget {
  const LocalManagementPage({super.key});

  @override
  State<LocalManagementPage> createState() => _LocalManagementPageState();
}

class _LocalManagementPageState extends State<LocalManagementPage> {
  final LocalService _localService = LocalService();

  List<LocalRecord> _locals = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLocals();
  }

  Future<void> _loadLocals() async {
    try {
      final locals = await _localService.loadLocals();

      if (!mounted) {
        return;
      }

      setState(() {
        _locals = locals;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron cargar los locales.')),
      );
    }
  }

  Future<void> _showLocalForm({LocalRecord? local}) async {
    final controller = TextEditingController(text: local?.name ?? '');

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(local == null ? 'Crear local' : 'Editar local'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nombre del local',
              hintText: 'Ingresá el nombre',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();

                if (value.isEmpty) {
                  return;
                }

                Navigator.pop(dialogContext, value);
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (name == null || name.trim().isEmpty) {
      return;
    }

    try {
      if (local == null) {
        await _localService.createLocal(name: name);
      } else {
        await _localService.updateLocalName(localId: local.id, name: name);
      }

      await _loadLocals();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            local == null
                ? 'Local creado correctamente.'
                : 'Local actualizado correctamente.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      final message = error.toString().replaceFirst('Exception: ', '');

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _changeLocalStatus(LocalRecord local, bool active) async {
    try {
      await _localService.updateLocalStatus(localId: local.id, active: active);

      await _loadLocals();
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo actualizar el estado del local.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administrar locales'),
        backgroundColor: greenColor,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showLocalForm(),
        backgroundColor: greenColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo local'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: greenColor))
            : _locals.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Todavía no hay locales creados.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: grayTextColor, fontSize: 16),
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
                itemCount: _locals.length,
                itemBuilder: (context, index) {
                  final local = _locals[index];

                  return Card(
                    elevation: 0,
                    color: Colors.white,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: local.active
                            ? const Color(0xFFE4F3EA)
                            : Colors.grey.shade200,
                        child: Icon(
                          Icons.store_outlined,
                          color: local.active ? greenColor : Colors.grey,
                        ),
                      ),
                      title: Text(
                        local.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        local.active ? 'Local activo' : 'Local desactivado',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Editar',
                            onPressed: () {
                              _showLocalForm(local: local);
                            },
                            icon: const Icon(
                              Icons.edit_outlined,
                              color: greenColor,
                            ),
                          ),
                          Switch(
                            value: local.active,
                            activeColor: greenColor,
                            onChanged: (value) {
                              _changeLocalStatus(local, value);
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class AccountManagementPage extends StatefulWidget {
  const AccountManagementPage({super.key});

  @override
  State<AccountManagementPage> createState() => _AccountManagementPageState();
}

class _AccountManagementPageState extends State<AccountManagementPage> {
  final AccountService _accountService = AccountService();

  List<AccountProfile> _accounts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    try {
      final accounts = await _accountService.loadAccounts();

      if (!mounted) {
        return;
      }

      setState(() {
        _accounts = accounts;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error cargando cuentas: $error')));
    }
  }

  Future<void> _changeStatus(AccountProfile account) async {
    try {
      await _accountService.updateAccountStatus(
        uid: account.uid,
        active: !account.active,
      );

      await _loadAccounts();
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo cambiar el estado de la cuenta.'),
        ),
      );
    }
  }

  void _showDetails(AccountProfile account) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(account.username),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                account.isAdministrator
                    ? 'Tipo: Administradora'
                    : 'Tipo: Local',
              ),
              const SizedBox(height: 8),
              Text('Email: ${account.email}'),
              const SizedBox(height: 8),
              Text('Estado: ${account.active ? 'Activa' : 'Bloqueada'}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administrar cuentas'),
        backgroundColor: greenColor,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: greenColor))
          : _accounts.isEmpty
          ? const Center(
              child: Text(
                'No hay cuentas registradas.',
                style: TextStyle(color: grayTextColor, fontSize: 16),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: _accounts.length,
              itemBuilder: (context, index) {
                final account = _accounts[index];

                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    onTap: () {
                      _showDetails(account);
                    },
                    leading: Icon(
                      account.isAdministrator
                          ? Icons.admin_panel_settings_outlined
                          : Icons.store_outlined,
                      color: greenColor,
                      size: 30,
                    ),
                    title: Text(
                      account.username,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${account.isAdministrator ? 'Administradora' : 'Local'}'
                      ' · ${account.active ? 'Activa' : 'Bloqueada'}',
                    ),

                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'status') {
                          _changeStatus(account);
                        }
                      },
                      itemBuilder: (context) {
                        return [
                          PopupMenuItem(
                            value: 'status',
                            child: Text(
                              account.active ? 'Bloquear' : 'Activar',
                            ),
                          ),
                        ];
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class GiftCardHistoryPage extends StatelessWidget {
  const GiftCardHistoryPage({super.key, required this.giftCards});

  final List<GiftCard> giftCards;

  Color _statusBackgroundColor(String status) {
    switch (status) {
      case 'Bloqueada':
        return const Color(0xFFFFF0D9);
      case 'Anulada':
        return const Color(0xFFFFE3E3);
      case 'Vencida':
        return const Color(0xFFE5E7EB);
      default:
        return const Color(0xFFE4F3EA);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Bloqueada':
        return const Color(0xFFB56A00);
      case 'Anulada':
        return const Color(0xFFB3261E);
      case 'Vencida':
        return const Color(0xFF374151);
      default:
        return greenColor;
    }
  }

  Future<void> _showDetails(BuildContext context, GiftCard giftCard) async {
    final usages = await GiftCardService().loadGiftCardUsages(giftCard.code);

    if (usages.isNotEmpty) {
      double parseAmount(Object? value) {
        final text = value?.toString() ?? '';

        final digitsOnly = text.replaceAll(RegExp(r'[^0-9]'), '');

        return double.tryParse(digitsOnly) ?? 0;
      }

      final originalAmount = parseAmount(giftCard.amount);

      final usedAmount = usages.fold<double>(0, (total, usage) {
        return total + parseAmount(usage['amountUsed']);
      });

      final remainingAmount = originalAmount - usedAmount;

      final status = remainingAmount <= 0
          ? 'Canjeada'
          : giftCard.status == 'Anulada'
          ? 'Anulada'
          : giftCard.status == 'Bloqueada'
          ? 'Bloqueada'
          : isGiftCardExpired(giftCard.expirationDate)
          ? 'Vencida'
          : 'Parcialmente usada';

      await showUsageReceipt(
        context: context,
        code: giftCard.code,
        username: usages.first['username']?.toString() ?? '',
        originalAmount: originalAmount.toStringAsFixed(0),
        usedAmount: usedAmount.toStringAsFixed(0),
        remainingAmount: remainingAmount.toStringAsFixed(0),
        status: status,
      );

      return;
    }

    final expirationText = giftCard.expirationDate == null
        ? 'Sin vencimiento'
        : formatDate(giftCard.expirationDate!);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Gift Card ${giftCard.code}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Importe: ${money(giftCard.amount)}'),
              const SizedBox(height: 8),
              Text('Vencimiento: $expirationText'),
              const SizedBox(height: 8),
              Text('Estado: ${giftCard.displayStatus}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    var searchText = '';
    var selectedStatus = 'Todos';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Gift Cards'),
        backgroundColor: greenColor,
        foregroundColor: Colors.white,
      ),
      body: StatefulBuilder(
        builder: (context, setLocalState) {
          final statuses = <String>{
            'Todos',
            ...giftCards.map((giftCard) => giftCard.displayStatus),
          }.toList();

          final filteredGiftCards = giftCards.where((giftCard) {
            final matchesSearch = giftCard.code.toLowerCase().contains(
              searchText.toLowerCase(),
            );

            final matchesStatus =
                selectedStatus == 'Todos' ||
                giftCard.displayStatus == selectedStatus;

            return matchesSearch && matchesStatus;
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: TextField(
                  decoration: InputDecoration(
                    labelText: 'Buscar por código',
                    hintText: 'Ejemplo: A01',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (value) {
                    setLocalState(() {
                      searchText = value;
                    });
                  },
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: DropdownButtonFormField<String>(
                  value: selectedStatus,
                  decoration: InputDecoration(
                    labelText: 'Filtrar por estado',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: statuses.map((status) {
                    return DropdownMenuItem<String>(
                      value: status,
                      child: Text(status),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }

                    setLocalState(() {
                      selectedStatus = value;
                    });
                  },
                ),
              ),

              Expanded(
                child: filteredGiftCards.isEmpty
                    ? const Center(
                        child: Text(
                          'No se encontraron Gift Cards.',
                          style: TextStyle(color: grayTextColor, fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        itemCount: filteredGiftCards.length,
                        itemBuilder: (context, index) {
                          final giftCard = filteredGiftCards[index];

                          final expirationText = giftCard.expirationDate == null
                              ? 'Sin vencimiento'
                              : formatDate(giftCard.expirationDate!);

                          return Card(
                            elevation: 0,
                            color: Colors.white,
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              onTap: () {
                                _showDetails(context, giftCard);
                              },
                              leading: CircleAvatar(
                                backgroundColor: _statusBackgroundColor(
                                  giftCard.displayStatus,
                                ),
                                child: Icon(
                                  Icons.card_giftcard_rounded,
                                  color: _statusColor(giftCard.displayStatus),
                                ),
                              ),
                              title: Text(
                                'Gift Card ${giftCard.code}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                'Importe: ${money(giftCard.amount)}\n'
                                'Vence: $expirationText',
                              ),
                              isThreeLine: true,
                              trailing: Chip(
                                label: Text(giftCard.displayStatus),
                                backgroundColor: _statusBackgroundColor(
                                  giftCard.displayStatus,
                                ),
                                labelStyle: TextStyle(
                                  color: _statusColor(giftCard.displayStatus),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class LocalQrScannerPage extends StatefulWidget {
  const LocalQrScannerPage({super.key});

  @override
  State<LocalQrScannerPage> createState() => _LocalQrScannerPageState();
}

class _LocalQrScannerPageState extends State<LocalQrScannerPage> {
  final MobileScannerController _scannerController = MobileScannerController();

  bool _alreadyScanned = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _handleDetection(BarcodeCapture capture) {
    if (_alreadyScanned) {
      return;
    }

    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;

      if (value == null || value.trim().isEmpty) {
        continue;
      }

      _alreadyScanned = true;
      _scannerController.stop();

      var scannedCode = value.trim();

      if (scannedCode.startsWith('GiftCheck|')) {
        final parts = scannedCode.split('|');

        if (parts.length > 1) {
          scannedCode = parts[1].trim();
        }
      }

      Navigator.pop(context, scannedCode);

      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear QR'),
        backgroundColor: greenColor,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _handleDetection,
          ),

          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: Text(
              'Apuntá la cámara al código QR de la Gift Card.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
                shadows: [Shadow(color: Colors.black, blurRadius: 5)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class UsageHistoryPage extends StatefulWidget {
  const UsageHistoryPage({super.key});

  @override
  State<UsageHistoryPage> createState() => _UsageHistoryPageState();
}

class _UsageHistoryPageState extends State<UsageHistoryPage> {
  final GiftCardService _giftCardService = GiftCardService();
  StreamSubscription<List<Map<String, dynamic>>>? _usagesSubscription;

  final Map<String, List<Map<String, dynamic>>> _usagesByCode = {};

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _listenUsageHistory();
  }

  void _listenUsageHistory() {
    _usagesSubscription = _giftCardService.watchAllGiftCardUsages().listen(
      (usages) {
        final grouped = <String, List<Map<String, dynamic>>>{};

        for (final usage in usages) {
          final code = usage['giftCardCode']?.toString() ?? '';

          if (code.isEmpty) {
            continue;
          }

          grouped.putIfAbsent(code, () => []);
          grouped[code]!.add(usage);
        }

        if (!mounted) {
          return;
        }

        setState(() {
          _usagesByCode
            ..clear()
            ..addAll(grouped);
          _loading = false;
        });
      },
      onError: (_) async {
        if (!mounted) {
          return;
        }

        setState(() {
          _loading = false;
        });

        await showGiftCheckErrorDialog(
          context: context,
          title: 'No se pudo actualizar el historial',
          message:
              'No pudimos actualizar los movimientos en este momento. '
              'Verificá la conexión e intentá nuevamente.',
        );
      },
    );
  }

  @override
  void dispose() {
    _usagesSubscription?.cancel();
    super.dispose();
  }

  double _parseAmount(Object? value) {
    final text = value?.toString() ?? '';

    final digitsOnly = text.replaceAll(RegExp(r'[^0-9]'), '');

    return double.tryParse(digitsOnly) ?? 0;
  }

  Future<void> _openGiftCardDetails(
    String code,
    List<Map<String, dynamic>> usages,
  ) async {
    try {
      final giftCardData = await _giftCardService.findGiftCardByCode(code);

      if (!mounted) {
        return;
      }

      if (giftCardData == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se encontró la Gift Card.')),
        );
        return;
      }

      final originalAmount = _parseAmount(giftCardData['amount']);

      final totalUsedFromRecords = usages.fold<double>(0, (total, usage) {
        return total + _parseAmount(usage['amountUsed']);
      });

      final usedAmount = giftCardData['usedAmount'] == null
          ? totalUsedFromRecords
          : _parseAmount(giftCardData['usedAmount']);

      final remainingAmount = giftCardData['remainingAmount'] == null
          ? originalAmount - usedAmount
          : _parseAmount(giftCardData['remainingAmount']);

      final rawExpirationValue = giftCardData['expirationDate'];
      final rawExpirationDate = rawExpirationValue is Timestamp
          ? rawExpirationValue.toDate()
          : null;

      await showUsageReceipt(
        context: context,
        code: code,
        username: usages.first['username']?.toString() ?? '',
        originalAmount: originalAmount.toStringAsFixed(0),
        usedAmount: usedAmount.toStringAsFixed(0),
        remainingAmount: remainingAmount.toStringAsFixed(0),
        status: effectiveGiftCardStatus(
          giftCardData['status']?.toString() ?? 'Activa',
          rawExpirationDate,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('ERROR AL GUARDAR GIFT CARD: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      await showGiftCheckErrorDialog(
        context: context,
        title: 'No se pudo abrir el detalle',
        message:
            'No pudimos cargar los movimientos de esta Gift Card. '
            'Verificá la conexión e intentá nuevamente.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final codes = _usagesByCode.keys.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de usos'),
        backgroundColor: greenColor,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: greenColor))
          : codes.isEmpty
          ? const Center(
              child: Text(
                'Todavía no hay usos registrados.',
                style: TextStyle(color: grayTextColor, fontSize: 16),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: codes.length,
              itemBuilder: (context, index) {
                final code = codes[index];
                final usages = _usagesByCode[code] ?? [];

                final totalUsed = usages.fold<double>(0, (total, usage) {
                  return total + _parseAmount(usage['amountUsed']);
                });

                final latestUsage = usages.first;

                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: Color(0xFFDCE9E0)),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () {
                      _openGiftCardDetails(code, usages);
                    },
                    child: Container(
                      decoration: const BoxDecoration(
                        border: Border(
                          left: BorderSide(color: greenColor, width: 5),
                        ),
                      ),
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const CircleAvatar(
                                backgroundColor: Color(0xFFE4F3EA),
                                child: Icon(
                                  Icons.receipt_long_outlined,
                                  color: greenColor,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Gift Card $code',
                                  style: const TextStyle(
                                    color: darkTextColor,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: greenColor,
                              ),
                            ],
                          ),

                          const SizedBox(height: 18),

                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Total utilizado',
                                      style: TextStyle(
                                        color: grayTextColor,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      money(totalUsed.toStringAsFixed(0)),
                                      style: const TextStyle(
                                        color: greenColor,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${usages.length} '
                                  '${usages.length == 1 ? 'uso' : 'usos'}',
                                  style: const TextStyle(
                                    color: darkTextColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          const Divider(height: 1, color: Color(0xFFE5ECE7)),

                          const SizedBox(height: 12),

                          Text(
                            'Último uso: '
                            '${latestUsage['username'] ?? ''}',
                            style: const TextStyle(
                              color: darkTextColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),

                          const SizedBox(height: 4),

                          Text(
                            formatUsageDate(latestUsage['usedAt']),
                            style: const TextStyle(
                              color: grayTextColor,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
