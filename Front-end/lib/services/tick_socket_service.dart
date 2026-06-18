import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class TickSocketService {
  WebSocketChannel? _channel;
  bool _isConnected = false;

  void connect(
      String symbol,
      Function(Map<String, dynamic> data) onTick,
      ) {
    dispose(); // always close previous connection

    _channel = WebSocketChannel.connect(
      Uri.parse("ws://10.0.2.2:8000/ws/ticks/$symbol/"),
    );

    _isConnected = true;

    _channel!.stream.listen(
          (event) {
        try {
          final data = jsonDecode(event as String);
          onTick(data);
        } catch (e) {
          // ignore bad packets
        }
      },
      onError: (e) {
        _isConnected = false;
      },
      onDone: () {
        _isConnected = false;
      },
      cancelOnError: true,
    );
  }

  bool get isConnected => _isConnected;

  void dispose() {
    _isConnected = false;
    _channel?.sink.close();
    _channel = null;
  }
}