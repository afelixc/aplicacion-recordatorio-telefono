# Las notificaciones programadas se guardan con Gson; que la optimización del
# APK no borre ni renombre lo que necesita para leerlas a la hora del aviso.
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.dexterous.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class sk.fourq.otaupdate.** { *; }

# WorkManager (revisar el calendario con la app cerrada) guarda sus tareas en
# una base Room que se crea por reflexión al arrancar la app. Si la optimización
# le borra el constructor, la app se cierra apenas se abre (pasó en la v1.0.27).
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
