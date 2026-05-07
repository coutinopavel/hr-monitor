# Monitor de Frecuencia Cardiaca

App de monitoreo de frecuencia cardiaca en tiempo real usando un sensor con pletismografia de luz infrarroja y luz roja.

## Componentes

- Sensor MAX30102
- Microcontrolador Seeed XIAO nRF52840
- Celular Android
- Computadora para compilar y enviar APK

## Estructura del repo

- `lib/`: app Flutter
- `hr_arduino/heart_monitor_final/`: firmware Arduino
- `Firmware/`: archivos del firmware (si aplica)

## Requisitos de software

- Flutter SDK (canal estable)
- Android SDK / Android Studio
- Arduino IDE
- Drivers del microcontrolador (si aplica)

## Configuracion del firmware (Arduino)

1. Copia el archivo `hr_arduino/heart_monitor_final/heart_monitor_final.ino` a una carpeta fuera del repositorio.
2. Abre el .ino en el Arduino IDE.
3. Selecciona la placa correspondiente a Seeed XIAO nRF52840.
4. Compila y sube el firmware al microcontrolador.

Nota: el Arduino IDE puede fallar si el .ino esta dentro del repositorio; moverlo a otra carpeta evita conflictos de rutas.

## Configuracion de la app Flutter

1. Abre este repo en tu editor.
2. Instala dependencias:

```bash
flutter pub get
```

3. Conecta un dispositivo Android o inicia un emulador.
4. Ejecuta la app:

```bash
flutter run
```

## Generar APK

```bash
flutter build apk --release
```

El APK quedara en `build/app/outputs/flutter-apk/`.

## Uso

1. Enciende el microcontrolador con el sensor conectado.
2. Abre la app en el celular.
3. Verifica que se muestren las lecturas en tiempo real.

## Problemas comunes

- Si el Arduino IDE no abre el .ino, confirma que este fuera del repo.
- Si Flutter no encuentra el dispositivo, revisa `adb devices` y permisos USB.

## Pendientes

- Agregar diagrama de conexion del sensor.
- Documentar el protocolo de comunicacion entre firmware y app.
- Incluir capturas de pantalla de la app.

## Licencia

Pendiente por definir.