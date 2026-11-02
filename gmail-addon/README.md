# Recordame en la barra de Gmail

Complemento de Gmail (Apps Script) para ver y manejar los recordatorios de
Recordame desde la compu: tildar como hecho, crear, cambiar y borrar.

Funciona con dos archivos en Google Drive que crea el teléfono
(Configuración → Gmail en la compu, recuadro escondido: 5 toques en la versión):

- `Recordame-gmail.json`: la lista. La escribe solo el teléfono.
- `Recordame-gmail-cambios.json`: lo hecho en Gmail. Lo escribe solo este
  complemento; el teléfono lo aplica y avisa en la lista cuáles ya aplicó.

## Instalarlo (una sola vez, en la compu)

1. Entrá a [script.google.com](https://script.google.com) con la cuenta de Gmail
   donde lo querés ver → **Nuevo proyecto** → nombre: **Recordame**.
2. En la ruedita ⚙ (Configuración del proyecto) tildá
   **Mostrar el archivo de manifiesto "appsscript.json" en el editor**.
3. Volvé al editor (`< >`):
   - Abrí `appsscript.json`, borrá todo y pegá el contenido de
     [appsscript.json](appsscript.json).
   - Abrí `Código.gs`, borrá todo y pegá el contenido de
     [Codigo.gs](Codigo.gs).
   - Tocá 💾 Guardar.
4. **Implementar → Implementaciones de prueba → Instalar → Listo**.
5. Abrí Gmail y recargá la página: a la derecha aparece la campanita.
6. La primera vez: **Autorizar el acceso** → elegí tu cuenta → "Google no
   verificó esta app" → **Configuración avanzada → Ir a Recordame (no seguro)
   → Permitir**. Es normal: la app es tuya y nadie la revisó.

Si el Drive del teléfono es de otra cuenta que este Gmail, compartí la carpeta
de los dos archivos con esta cuenta como **Editor**.
