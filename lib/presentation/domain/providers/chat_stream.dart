import 'package:bloc/bloc.dart';

class ChatStream extends Cubit<String> {
  ChatStream() : super('');

  void updateChat(String newChat) {
    emit(newChat);
  }
}
