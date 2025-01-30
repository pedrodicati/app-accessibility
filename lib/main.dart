import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

// Constantes para mensagens TTS
const String welcomeMessage =
    "Bem-vindo ao seu assistente visual. Para utilizar, aponte a câmera para o que você deseja analisar. "
    "Toque na tela para capturar uma foto e começar a gravar sua pergunta. "
    "Toque novamente para finalizar a gravação. Aguarde a resposta em áudio.";

void main() {
  // Garante que o binding seja inicializado antes de qualquer outra coisa
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa a câmera de forma assíncrona
  initializeCamera();
}

Future<void> initializeCamera() async {
  try {
    final cameras = await availableCameras();
    runApp(MyApp(cameras: cameras));
  } catch (e) {
    print('Error initializing cameras: $e');
    runApp(const ErrorApp());
  }
}

class ErrorApp extends StatelessWidget {
  const ErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.error_outline, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text(
                'Erro ao inicializar a câmera.\nPor favor, verifique as permissões do aplicativo.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CameraScreen(cameras: cameras),
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(), // Tema escuro para melhor contraste
    );
  }
}

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  late FlutterTts flutterTts;
  late FlutterSoundRecorder audioRecorder;
  bool _isInitialized = false;
  bool _isRecording = false;
  bool _isProcessing = false;
  String? _audioPath;
  String? _imagePath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initialize() async {
    try {
      bool permissions = await _checkPermissions();
      if (!permissions) {
        await flutterTts.speak(
            "Por favor, conceda as permissões necessárias para o aplicativo funcionar.");
        return;
      }

      await _initializeCamera();
      await _initializeTts();
      await _initializeAudioRecorder();
    } catch (e) {
      print('Error in initialization: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro na inicialização: $e')),
        );
      }
    }
  }

  Future<bool> _checkPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
      Permission.storage,
    ].request();

    return statuses.values.every((status) => status.isGranted);
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) return;

    try {
      _controller = CameraController(
        widget.cameras[0],
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller?.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      print('Error initializing camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao inicializar a câmera: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _initializeTts() async {
    flutterTts = FlutterTts();
    await flutterTts.setLanguage("pt-BR");
    await flutterTts.setSpeechRate(0.6);
    await flutterTts.setPitch(1.0);
    // await flutterTts.setVoice({"name": "", "locale": "pt-BR"});
    List<dynamic> voices = await flutterTts.getVoices;
    print(voices);

    await Future.delayed(const Duration(seconds: 1));
    await flutterTts.speak(welcomeMessage);
  }

  Future<void> _initializeAudioRecorder() async {
    audioRecorder = FlutterSoundRecorder();
    await audioRecorder.openRecorder();
    await audioRecorder
        .setSubscriptionDuration(const Duration(milliseconds: 10));
  }

  Future<void> _handleScreenTap() async {
    if (_isProcessing) return; // Evita múltiplos toques durante o processamento

    if (!_isRecording) {
      await _startCapture();
    } else {
      await _stopCapture();
    }
  }

  Future<void> _startCapture() async {
    if (!_isRecording) {
      try {
        final XFile photo = await _controller!.takePicture();
        _imagePath = photo.path;

        final tempDir = await getTemporaryDirectory();
        _audioPath =
            '${tempDir.path}/audio_query_${DateTime.now().millisecondsSinceEpoch}.wav';

        await audioRecorder.startRecorder(
          toFile: _audioPath,
          codec: Codec.pcm16WAV,
        );

        setState(() {
          _isRecording = true;
        });

        // Feedback sonoro e visual
        await flutterTts.speak("Gravando sua pergunta");
        _showFeedback("Gravando...");
      } catch (e) {
        print('Error during capture: $e');
        await flutterTts.speak("Ocorreu um erro ao iniciar a captura");
        _showFeedback("Erro ao iniciar captura");
      }
    }
  }

  Future<void> _stopCapture() async {
    if (_isRecording) {
      try {
        await audioRecorder.stopRecorder();
        setState(() {
          _isRecording = false;
          _isProcessing = true;
        });

        await flutterTts
            .speak("Processando sua solicitação, por favor aguarde");
        _showFeedback("Processando...");

        await _sendRequest();
      } catch (e) {
        print('Error stopping capture: $e');
        await flutterTts.speak("Ocorreu um erro ao finalizar a captura");
        _showFeedback("Erro ao finalizar captura");
      } finally {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _sendRequest() async {
    try {
      // Simulação de API - substituir pela URL real quando disponível
      await Future.delayed(const Duration(seconds: 6));

      // Exemplo de como será a implementação real
      /*
      final uri = Uri.parse('sua_url_api/analyze');
      var request = http.MultipartRequest('POST', uri);
      
      request.files.addAll([
        await http.MultipartFile.fromPath('image', _imagePath!),
        await http.MultipartFile.fromPath('audio', _audioPath!),
      ]);

      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      final jsonResponse = jsonDecode(responseData);
      final description = jsonResponse['description'];
      */

      // Resposta simulada - remover quando a API estiver pronta
      const description =
          "Na imagem eu vejo uma sala bem iluminada com uma mesa de madeira e algumas cadeiras. "
          "Há também uma janela grande que permite a entrada de luz natural.";

      await flutterTts.speak(description);

      // Limpa os arquivos temporários de forma segura
      await _cleanupFiles();
    } catch (e) {
      print('Error sending request: $e');
      await flutterTts.speak(
          "Ocorreu um erro ao processar sua solicitação. Por favor, tente novamente.");
      _showFeedback("Erro no processamento");
    }
  }

  Future<void> _cleanupFiles() async {
    try {
      if (_imagePath != null && await File(_imagePath!).exists()) {
        await File(_imagePath!).delete();
      }
      if (_audioPath != null && await File(_audioPath!).exists()) {
        await File(_audioPath!).delete();
      }
    } catch (e) {
      print('Error cleaning up files: $e');
    }
  }

  void _showFeedback(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    flutterTts.stop();
    audioRecorder.closeRecorder();
    _cleanupFiles();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Calcula as dimensões corretas para o preview da câmera
    final size = MediaQuery.of(context).size;
    final scale = 1 / (_controller!.value.aspectRatio * size.aspectRatio);

    return Scaffold(
      body: Stack(
        children: [
          GestureDetector(
            onTapDown: (_) => _handleScreenTap(),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.center,
              child: Center(
                child: CameraPreview(_controller!),
              ),
            ),
          ),
          if (_isRecording)
            const Positioned(
              top: 50,
              right: 20,
              child: Icon(
                Icons.mic,
                color: Colors.red,
                size: 30,
              ),
            ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          // Indicador de feedback tátil
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isRecording ? "Toque para parar" : "Toque para começar",
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
