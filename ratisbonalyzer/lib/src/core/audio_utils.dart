import 'package:audioplayers/audioplayers.dart';

final AudioPlayer _audioPlayer = AudioPlayer();

void playBoingSound() async {
  try {
    if (_audioPlayer.state == PlayerState.playing) {
      await _audioPlayer.stop();
    }
    await _audioPlayer.play(AssetSource('sounds/boing.mp3'));
  } catch (_) {
    // Fail silently
  }
}
