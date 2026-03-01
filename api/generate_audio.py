import pyttsx3
engine = pyttsx3.init()
engine.save_to_file("The front left rim looks rusty and I think a lug nut is missing.", "test_audio.wav")
engine.runAndWait()
