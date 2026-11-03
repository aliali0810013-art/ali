# توقيع Android النهائي

حزم `PREPUBLISH` تستخدم توقيع Android التجريبي لتسهيل التثبيت والاختبار فقط.

قبل توزيع النسخة الإنتاجية أو رفعها إلى متجر:

1. أنشئ مفتاح إصدار مملوكًا للمنتج واحتفظ به ونسخة احتياطية منه في مكان آمن.
2. انسخ `android/key.properties.example` إلى `android/key.properties`.
3. ضع مسار المفتاح والاسم وكلمات المرور الحقيقية في الملف المحلي.
4. نفّذ `flutter build appbundle --release` أو `flutter build apk --release`.
5. تحقق من الشهادة بواسطة `apksigner verify --print-certs`، ويجب ألا يكون اسمها `Android Debug`.

الملف `key.properties` وملفات `jks/keystore` مستثناة من Git. فقدان مفتاح الإصدار يمنع إصدار تحديثات موقعة للتطبيق نفسه.
