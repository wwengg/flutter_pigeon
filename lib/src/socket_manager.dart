import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_pigeon/flutter_pigeon.dart';
import 'package:protobuf/protobuf.dart' as $pb;

class SocketManage {
  final String ip;
  final int port;
  Socket _socket;
  Stream<List<int>> _stream;
  Timer _timer;
  bool _connected = false;
  bool isConnecting = false;
  Int8List cacheData = Int8List(0);

  SocketManage(this.ip, this.port);

  Map msgHandlerPool;

  addHandle(int op, Function function) {
    msgHandlerPool[op] = function;
  }

  getHandle(int op) {
    if (msgHandlerPool.containsKey(op)) {
      return msgHandlerPool[op];
    } else {
      return null;
    }
  }

  void decodeHandle(newData) {
    cacheData = Int8List.fromList(cacheData + newData);
    while (cacheData.length >= 16) {
      var byteData = cacheData.buffer.asByteData();
      int pbLen = byteData.getInt32(0);
      int op = byteData.getInt32(4);
      int ver = byteData.getInt32(8);
      int seq = byteData.getInt32(12);
      // 数据长度小于消息长度，数据不完整，暂不处理
      if (cacheData.length < pbLen + 16) {
        return;
      }
      Int8List pbBody;
      if (pbLen > 0) {
        pbBody = cacheData.sublist(16, 16 + pbLen);
      }
      // 整理缓存数据
      int totalLen = 16 + pbLen;
      cacheData = cacheData.sublist(totalLen, cacheData.length);

      Function handler = msgHandlerPool[op];
      if (handler == null) {
        print("没有找到消息号$op的处理器");
        return;
      }
      handler(pbBody);
    }
  }

  void errorHandler(error, StackTrace trace) {
    print("捕获socket异常信息：error=$error，trace=${trace.toString()}");
    _timer.cancel();
    _socket.close();
    _connected = false;
  }

  void doneHandler() {
    _timer.cancel();
    _socket.destroy();
    print("socket关闭处理");
    _connected = false;
  }

  getConnected() {
    return _connected;
  }

  initSocket({int attempts = 1}) async {
    isConnecting = true;
    int k = 1;
    while (k <= attempts) {
      try {
        _socket =
            await Socket.connect(ip, port, timeout: new Duration(seconds: 5));
        break;
      } catch (Exception) {
        print(
            k.toString() + " attempt: Socket not connected (Timeout reached)");
        if (k == attempts) {
          isConnecting = false;
          return;
        }
        k += 1;
      }
    }
    _connected = true;
    isConnecting = false;
    print("Socket successfully connected");
    // _socket.listen((List<int> event) async {});
    _socket.listen(decodeHandle,
        onError: errorHandler, onDone: doneHandler, cancelOnError: false);

    _timer = Timer.periodic(Duration(seconds: 3), (t) {
      print("send heart");
      addParams(0);
      // lastSendHeartTime = new DateTime.now().millisecondsSinceEpoch;
    });
  }

  addParams(int op, [$pb.GeneratedMessage pb]) {
    //序列化pb对象
    Uint8List pbBody;
    int pbLen = 0;
    if (pb != null) {
      pbBody = pb.writeToBuffer();
      pbLen = pbBody.length;
    }

    var header = ByteData(16);
    header.setInt32(0, pbLen, Endian.little);
    header.setInt32(4, op, Endian.little);
    header.setInt32(8, 1, Endian.little);
    header.setInt32(12, 0, Endian.little);
    var msg = pbBody == null
        ? header.buffer.asUint8List()
        : header.buffer.asUint8List() + pbBody.buffer.asUint8List();
    //给服务器发消息
    try {
      _socket.add(msg);
      print("给服务端发送消息，消息号=$op");
    } catch (e) {
      print("send捕获异常：msgCode=$op，e=${e.toString()}");
      _timer.cancel();
    }
  }
}
