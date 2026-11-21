# تقرير تنفيذ OCR والترجمة — Orion Subtitles

## ما تم تنفيذه

يأخذ التطبيق إطارات `CVPixelBuffer` من مسار Remote Play الداخلي بعد فك ترميز الفيديو، ثم يمررها إلى `VNRecognizeTextRequest` عبر Vision. يستخدم OCR المسار السريع، ويمرر اللغة الإنجليزية، ويقص منطقة normalized قابلة للتغيير برمجيًا. لا يستخدم التطبيق ReplayKit أو Broadcast Upload Extension ولا يحاول قراءة تطبيق آخر.

أضيف `TranslationCoordinator` لمنع التكرار، وإلغاء المهمة القديمة عند وصول إطار أحدث، والاحتفاظ بـcache للنصوص التي تمت ترجمتها، وإبقاء آخر نتيجة صحيحة أثناء انتظار نتيجة جديدة. يسجل `LatencyMetrics` أوقات التقاط الإطار وبدء وانتهاء OCR وانتهاء الترجمة والعرض. قيمة 250ms هي فاصل تقديم الإطارات إلى OCR فقط وليست ادعاءً بزمن ترجمة قدره 250ms.

أضيف جسر `AppleTranslationBridge` رسمي يعتمد على `TranslationSession` عبر SwiftUI `translationTask`. يطلب الزوج English → Arabic، ويفحص `LanguageAvailability` قبل معالجة الطلبات. عند توفر النماذج يستخدم الترجمة المحلية من Apple، وعند عدم توفرها أو رفض تنزيلها يرجع خطأ واضحًا بدل نص وهمي. حسب SDK الذي بُني به المشروع، واجهات `TranslationSession` و`translationTask` المستخدمة هنا متاحة ابتداءً من iPadOS 18، لذلك بقي deployment target للمشروع 17.0 ولم يتم الادعاء بأن الترجمة تعمل على الإصدارات الأقدم.

## ما لم يُثبت بعد

لم يتوفر iPad فعلي في بيئة التنفيذ، ولذلك لم أختبر اتصال PS5 الحقيقي، أو استخراج نص لعبة فعليًا، أو تنزيل نماذج English → Arabic، أو زمن OCR والترجمة على جهاز، أو ظهور ترجمة عربية فعلية أثناء اللعب. نجاح GitHub Actions يثبت أن الكود يتجمع وأن IPA يتولد، لكنه لا يثبت اختبار runtime.

وضع الشاشة السوداء موجود كواجهة عالية التباين وعرض عربي داخل تجربة البث، لكنه لا أعتبره مكتملًا كنافذة مستقلة مرتبطة بمصدر Remote Play قبل اختبار التفاعل على iPad. لا يوجد زر منطقة وهمي؛ منطقة OCR موجودة في النموذج والخدمة، لكن واجهة السحب والتغيير المرئية تحتاج اختبارًا وتصميمًا إضافيًا.

## البناء

نجح Workflow رقم `44930296812` في GitHub Actions بتاريخ هذا الإصدار. نجحت خطوات بناء IPA، وفحص iPad-only وBundle ID، ورفع artifact `orion-subtitles-ipa`. آخر commit هو `a6e3d98`.

## المراجع

[1]: https://developer.apple.com/documentation/translation "Apple Translation framework"
[2]: https://developer.apple.com/documentation/translation/translating-text-within-your-app "Apple custom translation with SwiftUI"
[3]: https://developer.apple.com/documentation/vision/recognizing-text-in-images "Apple Vision text recognition"
[4]: https://developer.apple.com/documentation/replaykit "Apple ReplayKit"
