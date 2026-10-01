# GiftCheck con vouchers — listo para Visual Studio Code

Preparado el 1 de octubre de 2026 sobre `main`, commit `b12719997ef17bfb4ac769aee79775de396adfb6`, verificado contra GitHub.

## Abrir

En Visual Studio Code usá **Archivo → Abrir carpeta** y seleccioná tu carpeta original: `/Users/Usuario/Desktop/giftcheck`.

Los vouchers están integrados en el mismo repositorio de GiftCheck. Git muestra los archivos modificados y nuevos para revisar el cambio. La aplicación publicada no cambia hasta realizar el despliegue.

## Qué incluye

- **Crear voucher** disponible para administradoras y locales.
- Importes formateados al escribir con puntos de miles, cursor estable y pegado de texto. Valor entero separado del texto de presentación; al persistir se conserva la representación numérica sin separadores del esquema existente. Importe obligatorio, solo dígitos, mayor que cero; sin decimales. Se normalizan ceros iniciales. Máximo técnico: 999999999999 para mantener cálculos exactos.
- Vencimiento obligatorio, desde el día actual. Calendario en español con selector visible de mes, selector de año y grilla de días. Rango hasta el año 9999, límite de fecha de Firebase; no existe un año literalmente infinito. El día mínimo se recalcula al abrir el calendario y al confirmar.
- Validez hasta el final del día elegido, usando la zona horaria del dispositivo que emite. En la fecha máxima admitida se respeta el límite UTC de Firebase.
- Vista previa y confirmación antes de guardar. Imagen para compartir e historial unificado con pestañas Emitidos y Usos, incluyendo tarjetas sin usos.
- Diseño original de `GiftCardVisual`: blanco y negro, 535 × 650 para vouchers (Gift Cards conservan 535 × 785), mismo logo, borde, esquinas del QR, tipografía y tamaños. “VOU” conserva el texto relleno y “CHER” el contorno. Se quitan PARA/DE. Aparecen importe, vencimiento y, debajo, el código.
- Códigos de dos letras y seis números: `VA000001`, `VA000002`, etc. Al llegar a `VA999999`, sigue `VB000001`, hasta `VZ999999` (25.999.974 códigos). La reserva es transaccional y la serie VA–VZ queda reservada a vouchers para evitar cruces con Gift Cards. El contador no se borra ni se reinicia al borrar vouchers. Cancelar una vista previa puede dejar un número sin usar. El QR usa el formato existente `GiftCheck|código|Importe:…|Vence:…` y funciona con el mismo lector.
- Consulta manual, QR, usos parciales, saldo e historial compartidos con el circuito existente. En consultas y comprobantes se distingue Voucher de Gift Card.
- Orden administradora: Crear Gift Card, Crear voucher e historial. Sin escaneo ni ingreso manual. Orden local: Escanear QR, ingreso manual, Crear voucher e historial. Desde el detalle se puede compartir Gift Card o voucher; solo la administradora puede bloquear, anular o reactivar.
- Un voucher vencido muestra un aviso dedicado al consultarlo por QR o código; no permite abrir el formulario de uso. El servidor también impide consumos vencidos.
- Reglas de Firestore para que un local activo pueda emitir vouchers, sin permitirle emitir Gift Cards. Los usos de vouchers requieren actualizar saldo y comprobante juntos; se valida saldo, vencimiento y estado en Firebase.
- Reintentar un guardado con los mismos datos conserva el código para evitar duplicar el voucher si se pierde la respuesta de red.

## Ejecutar y publicar cuando corresponda

En la terminal de Visual Studio Code, dentro de `giftcheck`:

```sh
flutter pub get
flutter test
flutter build web --release
```

Para activar esta funcionalidad en la aplicación pública hay que publicar **las reglas y la web**, no solo la web:

```sh
firebase login
firebase deploy --only firestore:rules --project giftcheck-94700
firebase deploy --only hosting --project giftcheck-94700
```

Actualización publicada el 1 de octubre de 2026: reglas verificadas contra Firebase y despliegue web confirmado por la consola del usuario. No se requiere borrar datos, cambiar usuarios ni migrar Gift Cards. URL: https://giftcheck-94700.web.app.

## Archivos de la integración

- `lib/main.dart` y `lib/gift_card_service.dart`.
- `lib/voucher_pages.dart` y `lib/voucher_validation.dart`.
- `firestore.rules`, `pubspec.yaml` y `pubspec.lock`.
- `assets/fonts/`: las mismas fuentes Montserrat del diseño actual, incluidas localmente con su licencia.
- Pruebas en `test/`, `tests/firestore/` y `firebase.test.json`.

## Verificación

- Compilación web release y 22 pruebas Flutter aprobadas.
- Pruebas Flutter de formulario, calendario, validación, creación, reintento, consulta, usos parciales, saldo insuficiente, vencimiento y estados bloqueado/anulado.
- Verificación visual renderizada desde Flutter, incluyendo pantalla angosta y conservación del diseño de Gift Card.
- 14 escenarios en el emulador oficial de Firestore: permisos de ambos roles, rechazos de datos inválidos, uso parcial/total, inmutabilidad, historial obligatorio, vencimiento, bloqueo, consumos simultáneos y reserva concurrente de códigos.
- El análisis estático conserva avisos preexistentes del proyecto; no hay errores de compilación.

No se usaron datos productivos para las pruebas. No se probó la cámara ni el menú nativo de compartir en un iPhone físico.

Para repetir las pruebas de reglas se necesita Java 21+, Node y Firebase CLI:

```sh
npm ci --prefix tests/firestore
firebase emulators:exec --only firestore --project demo-giftcheck-vouchers --config firebase.test.json "node tests/firestore/voucher_rules.test.mjs"
```
