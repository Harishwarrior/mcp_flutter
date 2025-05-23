import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum ForwardingClientType { inspector, flutter }

/// Browser-compatible client for connecting to the forwarding server.
class ForwardingClient {
  WebSocketChannel? _ws;
  final Map<String, _PendingRequest> _pendingRequests = {};
  int _messageId = 0;
  Timer? _reconnectTimer;
  final int _reconnectDelay = 2000; // 2 seconds
  final String clientId;
  final ForwardingClientType clientType;
  final Map<String, Set<Function>> _eventHandlers = {};

  /// Creates a new forwarding client.
  ///
  /// @param clientType The type of client ('inspector' or 'flutter')
  /// @param clientId Optional client ID (will be generated if not provided)
  ForwardingClient(this.clientType, {String? clientId})
    : clientId = clientId ?? _generateUuid() {
    // Register ping method handler for connection testing
    _registerPingMethod();
  }

  /// Generate a UUID for the client ID
  static String _generateUuid() {
    return const Uuid().v4();
  }

  /// Generate a unique ID for requests
  String _generateId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${_messageId++}';
  }

  /// Add an event listener
  void on(String event, Function callback) {
    print('Adding event listener for: $event');
    _eventHandlers.putIfAbsent(event, () => {});
    _eventHandlers[event]!.add(callback);
    print('Event handlers for $event: ${_eventHandlers[event]!.length}');
  }

  /// Remove an event listener
  void off(String event, Function callback) {
    final handlers = _eventHandlers[event];
    if (handlers != null) {
      handlers.remove(callback);
    }
  }

  /// Emit an event
  void _emit(String event, [List<dynamic> args = const []]) {
    print('Emitting event: $event with args: $args');
    final handlers = _eventHandlers[event];
    if (handlers != null) {
      for (final handler in handlers) {
        print('Calling handler for event: $event');
        Function.apply(handler, args);
      }
    }

    // Special handling for 'method' event to also trigger method:${methodName} events
    if (event == 'method' && args.isNotEmpty) {
      final methodName = args[0];
      print('Looking for handlers for method:$methodName');
      final methodHandlers = _eventHandlers['method:$methodName'];
      if (methodHandlers != null) {
        print('Found ${methodHandlers.length} handlers for method:$methodName');
        // Skip the method name in args for specific method handlers
        final methodArgs = args.sublist(1);
        for (final handler in methodHandlers) {
          print('Calling handler for method:$methodName');
          Function.apply(handler, methodArgs);
        }
      } else {
        print('No handlers found for method:$methodName');
      }
    }
  }

  /// Connect to the forwarding server
  ///
  /// @param host Host address
  /// @param port Port number
  /// @param path WebSocket path
  Future<void> connect(
    String host,
    int port, {
    String path = '/forward',
  }) async {
    // Add a leading slash to path if not present
    if (path.isNotEmpty && !path.startsWith('/')) {
      path = '/$path';
    }

    // Check if we're already connected
    if (_ws != null && _isConnected()) {
      print('Already connected to forwarding server');
      return;
    }

    // If WebSocket exists but is not connected, close and recreate it
    if (_ws != null) {
      print('Closing existing WebSocket connection');
      try {
        await _ws!.sink.close();
      } catch (e) {
        print('Error closing WebSocket: $e');
      }
      _ws = null;
    }

    // Clear any existing reconnect timer
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    // Create a completer to handle the connection process
    final completer = Completer<void>();

    try {
      // Include clientType and clientId as query parameters
      final wsUrl =
          'ws://$host:$port$path?clientType=${clientType.name}&clientId=$clientId';
      print('Connecting to forwarding server at $wsUrl');

      // Create the WebSocket connection with more detailed error handling
      try {
        _ws = WebSocketChannel.connect(Uri.parse(wsUrl));
        print('WebSocket connection initiated');
      } catch (e, st) {
        print('Failed to create WebSocket connection: $e');
        print('Stack trace: $st');
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
        return completer.future;
      }

      // Setup a listener for incoming messages
      _ws!.stream.listen(
        (dynamic message) {
          try {
            final String messageStr = message.toString();
            print('Received WebSocket message: $messageStr');
            final Map<String, dynamic> parsedMessage =
                json.decode(messageStr) as Map<String, dynamic>;

            // Emit the message as an event
            _emit('message', [parsedMessage]);

            // Handle method calls
            if (parsedMessage.containsKey('method') &&
                parsedMessage.containsKey('id')) {
              print(
                'Processing method call: ${parsedMessage['method']} with id: ${parsedMessage['id']}',
              );
              _emit('method', [
                parsedMessage['method'],
                parsedMessage['params'],
                (final dynamic result) {
                  print(
                    'Respond callback called for method ${parsedMessage['method']} with result: $result',
                  );
                  _sendResponse(parsedMessage['id'] as String, result);
                },
              ]);
            }
            // Handle JSON-RPC responses
            else if (parsedMessage.containsKey('id')) {
              print('Processing response for id: ${parsedMessage['id']}');
              final request = _pendingRequests[parsedMessage['id']];
              if (request != null) {
                print('Found pending request for id: ${parsedMessage['id']}');
                if (parsedMessage.containsKey('error')) {
                  print('Completing with error: ${parsedMessage['error']}');
                  request.completer.completeError(
                    Exception(
                      parsedMessage['error']['message'] ?? 'Unknown error',
                    ),
                  );
                } else {
                  print('Completing with result: ${parsedMessage['result']}');
                  request.completer.complete(parsedMessage['result']);
                }
                _pendingRequests.remove(parsedMessage['id']);
              } else {
                print(
                  'No pending request found for id: ${parsedMessage['id']}',
                );
              }
            }
          } catch (error) {
            print('Error parsing WebSocket message: $error');
          }
        },
        onDone: () {
          print('Disconnected from forwarding server');
          _ws = null;
          _emit('disconnected');

          // Setup reconnect if not already set
          if (_reconnectTimer == null) {
            _setupReconnect(host, port, path: path);
          }
        },
        onError: (Object error) {
          print('WebSocket error: $error');
          _emit('error', [error]);
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        },
        cancelOnError: false,
      );

      // Complete the future once connection is established
      _emit('connected');

      // Start auto-reconnect if connection drops
      _setupReconnect(host, port, path: path);

      completer.complete();
    } catch (error) {
      print('Failed to create WebSocket: $error');
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }

    return completer.future;
  }

  /// Check if connected to the WebSocket
  bool _isConnected() {
    return _ws != null;
  }

  /// Send a JSON-RPC response
  ///
  /// @param id Request ID
  /// @param result Result value
  /// @param error Error object
  void _sendResponse(String id, dynamic result, {dynamic error}) {
    if (!_isConnected()) {
      print('Cannot send response: not connected');
      return;
    }

    final response = <String, dynamic>{'jsonrpc': '2.0', 'id': id};

    if (error != null) {
      response['error'] = error;
    } else {
      response['result'] = result;
    }

    final String jsonResponse = json.encode(response);
    final int responseLength = jsonResponse.length;

    print('Sending response for ID $id of size $responseLength bytes');
    try {
      _ws!.sink.add(jsonResponse);
      print('Response sent successfully');
    } catch (e, st) {
      print('Error sending WebSocket response: $e');
      print('Stack trace: $st');
    }
  }

  /// Setup automatic reconnection
  void _setupReconnect(String host, int port, {required String path}) {
    _reconnectTimer?.cancel();

    _reconnectTimer = Timer.periodic(Duration(milliseconds: _reconnectDelay), (
      _,
    ) {
      if (!_isConnected()) {
        print('Attempting to reconnect to forwarding server...');
        connect(host, port, path: path).catchError((final dynamic err) {
          print('Reconnect failed: $err');
        });
      }
    });
  }

  /// Call a method via the forwarding server
  ///
  /// @param method Method name
  /// @param params Method parameters
  /// @returns Future that resolves with the result
  Future<T> callMethod<T>(
    String method, {
    Map<String, dynamic> params = const {},
  }) async {
    if (!_isConnected()) {
      throw Exception('Not connected to forwarding server');
    }

    final id = _generateId();
    final request = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };

    final completer = Completer<T>();
    _pendingRequests[id] = _PendingRequest(
      completer: completer,
      method: method,
    );

    _ws!.sink.add(json.encode(request));
    return completer.future;
  }

  /// Send a raw message through the forwarding server
  ///
  /// @param message Message to send
  void sendMessage(dynamic message) {
    if (!_isConnected()) {
      throw Exception('Not connected to forwarding server');
    }

    _ws!.sink.add(json.encode(message));
  }

  /// Register a method handler
  ///
  /// @param method Method name
  /// @param handler Function to handle the method call
  void registerMethod(
    String method,
    Future<dynamic> Function(dynamic) handler,
  ) {
    print('Registering method handler for: $method');
    on('method:$method', (dynamic params, Function respond) async {
      print('Method $method called with params: $params');
      try {
        final result = await handler(params);
        print('Method $method completed with result: $result');
        respond(result);
      } catch (error) {
        print('Error handling method $method: $error');
        respond({
          'error': {'message': error.toString()},
        });
      }
    });
  }

  /// Register the flutter.test.ping method handler for connection testing
  void _registerPingMethod() {
    print('Registering flutter.test.ping method handler');
    registerMethod('flutter.test.ping', (dynamic params) async {
      print('Received ping with params: $params');
      return {
        'success': true,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'message': 'Flutter client is responsive',
        'clientId': clientId,
        'clientType': clientType.name,
      };
    });
  }

  /// Disconnect from the forwarding server
  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    if (_ws != null) {
      _ws!.sink.close();
      _ws = null;
    }
  }

  /// Check if connected to the forwarding server
  bool isConnected() {
    return _isConnected();
  }

  /// Get the client ID
  String getClientId() {
    return clientId;
  }

  /// Get the client type
  ForwardingClientType getClientType() {
    return clientType;
  }
}

/// Internal class to represent a pending request
class _PendingRequest {
  final Completer completer;
  final String method;

  _PendingRequest({required this.completer, required this.method});
}
