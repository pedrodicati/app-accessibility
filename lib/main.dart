import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CameraScreen(cameras: cameras),
      debugShowCheckedModeBanner: false,
    );
  }
}

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late FlutterTts flutterTts;
  late Record audioRecorder;
  bool _isInitialized = false;
  bool _isRecording = false;
  String? _audioPath;
  String? _imagePath;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeTts();
    _initializeAudioRecorder();
    _initializeVolumeButtonListener();
  }

  Future<void> _initializeCamera() async {
    _controller = CameraController(
      widget.cameras[0],
      ResolutionPreset.max,
      enableAudio: false,
    );

    try {
      await _controller.initialize();
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }

  Future<void> _initializeTts() async {
    flutterTts = FlutterTts();
    await flutterTts.setLanguage("pt-BR");
    await flutterTts.setSpeechRate(0.9);
    await flutterTts.setPitch(1.0);
    
    // Mensagem de boas-vindas com instruções
    await Future.delayed(const Duration(seconds: 1));
    await flutterTts.speak(
      "Bem-vindo ao seu assistente visual. Para utilizar, aponte a câmera para o que você deseja analisar. "
      "Pressione qualquer botão de volume para capturar uma foto e começar a gravar sua pergunta. "
      "Pressione novamente para finalizar a gravação. Aguarde a resposta em áudio."
    );
  }

  void _initializeAudioRecorder() {
    audioRecorder = Record();
  }

  void _initializeVolumeButtonListener() {
    HardwareKeyboard.instance.addHandler(_handleVolumeButton);
  }

  bool _handleVolumeButton(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.audioVolumeUp ||
          event.logicalKey == LogicalKeyboardKey.audioVolumeDown) {
        if (!_isRecording) {
          _startCapture();
        } else {
          _stopCapture();
        }
        return true;
      }
    }
    return false;
  }

  Future<void> _startCapture() async {
    if (!_isRecording) {
      // Captura a foto
      final XFile photo = await _controller.takePicture();
      _imagePath = photo.path;
      
      // Inicia a gravação
      final tempDir = await getTemporaryDirectory();
      _audioPath = '${tempDir.path}/audio_query.m4a';
      
      await audioRecorder.start(
        path: _audioPath,
        encoder: AudioEncoder.aacLc,
      );
      
      setState(() {
        _isRecording = true;
      });
      
      await flutterTts.speak("Gravando sua pergunta");
    }
  }

  Future<void> _stopCapture() async {
    if (_isRecording) {
      await audioRecorder.stop();
      setState(() {
        _isRecording = false;
      });
      
      await flutterTts.speak("Processando sua solicitação, por favor aguarde");
      
      await _sendRequest();
    }
  }

  Future<void> _sendRequest() async {
    try {
      // Simulando o tempo de processamento
      await Future.delayed(const Duration(seconds: 5));
      
      // Código preparado para quando a API estiver pronta
      /*
      final uri = Uri.parse('sua_url_api/analyze-image-audio-query');
      final request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath(
          'image',
          _imagePath!,
        ))
        ..files.add(await http.MultipartFile.fromPath(
          'audio',
          _audioPath!,
        ));

      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      final jsonResponse = jsonDecode(responseData);
      */
      
      // Mensagem simulada (remover quando a API estiver pronta)
      await flutterTts.speak(
        "Na imagem eu vejo uma sala bem iluminada com uma mesa de madeira e algumas cadeiras. "
        "Há também uma janela grande que permite a entrada de luz natural."
      );
      
      // Limpando os arquivos temporários
      await File(_imagePath!).delete();
      await File(_audioPath!).delete();
      
    } catch (e) {
      await flutterTts.speak("Ocorreu um erro ao processar sua solicitação. Por favor, tente novamente.");
      print('Error sending request: $e');
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleVolumeButton);
    _controller.dispose();
    flutterTts.stop();
    audioRecorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          SizedBox.expand(
            child: CameraPreview(_controller),
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
        ],
      ),
    );
  }
}