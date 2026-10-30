# Las notificaciones programadas se guardan con Gson; que la optimización del
# APK no borre ni renombre lo que necesita para leerlas a la hora del aviso.
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.dexterous.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class sk.fourq.otaupdate.** { *; }
