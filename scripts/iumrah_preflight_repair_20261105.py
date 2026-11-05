#!/usr/bin/env python3
"""Guarded, explicit-language source repair for the iumrah 2026-11-05 preflight log.

Run from the repository root:
 python3 scripts/iumrah_preflight_repair_20261105.py --check
 python3 scripts/iumrah_preflight_repair_20261105.py --apply

No silent fallbacks or modifications to business logic. Does not bypass CI.
"""
from __future__ import annotations
import argparse
import difflib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LANGS = ("turkish", "indonesian", "malay", "arabic")

def translations(*lines: str) -> dict[str,str]:
    assert len(lines) == 4
    return dict(zip(LANGS,lines))

SCOPE = {
    "makkahComfortShort": translations("Yalnızca Mekke", "Hanya Makkah", "Makkah sahaja", "مكة فقط"),
    "hotelFirstMakkah": translations("Yalnızca Mekke", "Hanya Makkah", "Makkah sahaja", "مكة فقط"),
    "makkahMadinahStandard": translations("Mekke + Medine", "Makkah + Madinah", "Makkah + Madinah", "مكة + المدينة"),
}
ESIM = {
    "left": translations("kaldı", "tersisa", "berbaki", "متبقي"),
    "ready": translations("Profil hazır. eSIM’i iPhone’unuzda etkinleştirin.", "Profil siap. Aktifkan eSIM di iPhone Anda.", "Profil sedia. Aktifkan eSIM pada iPhone anda.", "الملف جاهز. فعّل الشريحة الإلكترونية على iPhone."),
    "assigned": translations("eSIM seyahatinize bağlandı.", "eSIM telah ditautkan ke perjalanan Anda.", "eSIM telah dipautkan kepada perjalanan anda.", "تم ربط الشريحة الإلكترونية برحلتك."),
    "activate": translations("eSIM’i etkinleştir", "Aktifkan eSIM", "Aktifkan eSIM", "تفعيل الشريحة الإلكترونية"),
    "open": translations("eSIM’i aç", "Buka eSIM", "Buka eSIM", "فتح الشريحة الإلكترونية"),
    "packageOnly": translations("İlk sürümde eSIM yalnızca Umre paketine dahildir.", "Pada versi pertama, eSIM hanya tersedia dalam paket Umrah.", "Dalam versi pertama, eSIM hanya tersedia dalam pakej Umrah.", "في الإصدار الأول، تتوفر الشريحة الإلكترونية ضمن باقة العمرة فقط."),
    "details": translations("Paketler ve etkinleştirme", "Paket dan aktivasi", "Pelan dan pengaktifan", "الباقات والتفعيل"),
}
CITIES = {
    "makkah": translations("Mekke", "Makkah", "Makkah", "مكة"),
    "madinah": translations("Medine", "Madinah", "Madinah", "المدينة المنورة"),
}
MEALS = {
    "breakfast": translations("Kahvaltı", "Sarapan", "Sarapan", "الإفطار"),
    "lunch": translations("Öğle yemeği", "Makan siang", "Makan tengah hari", "الغداء"),
    "dinner": translations("Akşam yemeği", "Makan malam", "Makan malam", "العشاء"),
}
CALENDAR = {
    "title": translations("Tarihlerinizi seçin", "Pilih tanggal Anda", "Pilih tarikh anda", "اختر تواريخك"),
    "subtitle": translations("Yeşil günler iumrah tarafından yayımlanan direkt uçuşlardır", "Hari hijau menunjukkan penerbangan langsung yang diterbitkan iumrah", "Hari hijau menunjukkan penerbangan terus yang diterbitkan iumrah", "الأيام الخضراء تشير إلى رحلات مباشرة منشورة في iumrah"),
    "recommendedDirect": translations("iumrah AI öneriyor", "Direkomendasikan iumrah AI", "Disyorkan oleh iumrah AI", "موصى بها من iumrah AI"),
    "loading": translations("Yayımlanan direkt uçuşlar kontrol ediliyor…", "Memeriksa penerbangan langsung yang tersedia…", "Menyemak penerbangan terus yang diterbitkan…", "جارٍ التحقق من الرحلات المباشرة المنشورة…"),
    "directHint": translations("Yeşil günlerde iumrah envanterinde direkt uçuş vardır. Bu uçuşlar genellikle aktarmalı seçeneklerden daha kolay ve uygun fiyatlıdır.", "Hari hijau memiliki penerbangan langsung di inventaris iumrah. Biasanya lebih nyaman dan terjangkau dibanding penerbangan transit.", "Hari hijau mempunyai penerbangan terus dalam inventori iumrah. Biasanya lebih mudah dan berbaloi berbanding penerbangan transit.", "الأيام الخضراء لديها رحلات مباشرة في قاعدة iumrah، وهي عادةً أسهل وأفضل قيمة من رحلات الترانزيت."),
    "retry": translations("Yenile", "Muat ulang", "Muat semula", "تحديث"),
    "noDirectTitle": translations("Bu tarihlerde direkt uçuş yok", "Tidak ada penerbangan langsung pada tanggal ini", "Tiada penerbangan terus pada tarikh ini", "لا توجد رحلات مباشرة في هذه التواريخ"),
    "noDirectInlineBody": translations("Esnek tarihlerle devam edebilirsiniz. Sistem, daha yüksek fiyatlı bir veya iki aktarmalı uçuş önerebilir. Bu durum paketinizin toplamını etkiler.", "Anda dapat melanjutkan dengan tanggal fleksibel, tetapi sistem mungkin menawarkan penerbangan dengan satu atau dua transit dan harga lebih tinggi. Ini memengaruhi total paket Anda.", "Anda boleh meneruskan dengan tarikh fleksibel, tetapi sistem mungkin menawarkan penerbangan dengan satu atau dua transit pada harga lebih tinggi. Ini menjejaskan jumlah pakej anda.", "يمكنك المتابعة بتواريخ مرنة، لكن قد يعرض النظام رحلات بتوقف واحد أو توقفين بسعر أعلى، ما يؤثر على السعر النهائي للباقة."),
    "noDirectPopupBody": translations("iumrah envanterinde seçtiğiniz tarihler için yayımlanmış direkt gidiş-dönüş uçuş çifti yok. Esnek arama, paketinizin fiyatını artırabilecek bir veya iki aktarmalı seçenekler bulabilir.", "Saat ini tidak ada pasangan penerbangan langsung yang diterbitkan iumrah untuk tanggal pilihan Anda. Pencarian fleksibel dapat menemukan opsi satu atau dua transit dengan tarif lebih tinggi, sehingga menaikkan total paket.", "Tiada pasangan penerbangan terus yang diterbitkan iumrah untuk tarikh pilihan anda. Carian fleksibel mungkin menemui penerbangan dengan satu atau dua transit pada harga lebih tinggi dan meningkatkan jumlah pakej.", "لا تتوفر حاليًا في iumrah رحلتا ذهاب وعودة مباشرتان منشورتان للتواريخ المختارة. قد يجد البحث المرن خيارات بتوقف أو توقفين بسعر أعلى، ما يزيد إجمالي الباقة."),
    "inventoryNote": translations("Yeşil günler yalnızca iumrah veri tabanında yayımlanan uçuşlardan alınır. Diğer günler otomatik olarak direkt uçuş sayılmaz.", "Hari hijau hanya berasal dari penerbangan yang diterbitkan di basis data iumrah. Hari lain tidak otomatis ditandai sebagai penerbangan langsung.", "Hari hijau hanya berdasarkan penerbangan yang diterbitkan dalam pangkalan data iumrah. Hari lain tidak ditandakan sebagai penerbangan terus secara automatik.", "تُحدد الأيام الخضراء فقط من الرحلات المنشورة في قاعدة بيانات iumrah. لا تُصنّف الأيام الأخرى تلقائيًا على أنها رحلات مباشرة."),
    "reset": translations("Sıfırla", "Atur ulang", "Tetapkan semula", "إعادة ضبط"),
    "chooseDates": translations("Devam et", "Lanjutkan", "Teruskan", "متابعة"),
    "chooseDirectDates": translations("Direkt uçuş tarihlerini seç", "Pilih tanggal penerbangan langsung", "Pilih tarikh penerbangan terus", "اختر تواريخ الرحلات المباشرة"),
    "continueFlexible": translations("Esnek tarihlerle devam et", "Lanjutkan dengan tanggal fleksibel", "Teruskan dengan tarikh fleksibel", "المتابعة بتواريخ مرنة"),
    "directAccessibility": translations("Yayımlanmış direkt uçuş", "Penerbangan langsung yang diterbitkan", "Penerbangan terus yang diterbitkan", "رحلة مباشرة منشورة"),
}

SPEC = [
    ("Sources/Views/Home/HomeAppleStoreSections.swift", "switch (preview.kind, language) {", SCOPE, 1),
    ("Sources/Views/Home/HomeDashboardView.swift", "switch (settings.language, key) {", ESIM, 0),
    ("Sources/Views/Package/FinalPackageView.swift", "switch (settings.language, city) {", CITIES, 0),
    ("Sources/Views/Tabs/HotelsHomeView.swift", "switch (preview.kind, language) {", SCOPE, 1),
    ("Sources/Views/Tabs/HotelsHomeView.swift", "switch (settings.language, meal) {", MEALS, 0),
    ("Sources/Views/Trip/FlightDateCalendarView.swift", "switch (settings.language, key) {", CALENDAR, 0),
]

class RepairError(Exception):
    pass

def switch_span(text: str, anchor: str) -> tuple[int,int]:
    start = text.find(anchor)
    if start < 0 or text.find(anchor,start+len(anchor)) >= 0:
        raise RepairError(f"Expected one anchor, found {text.count(anchor)}: {anchor}")
    open_brace = start + len(anchor)-1
    depth, i = 1, open_brace+1
    while i < len(text) and depth:
        if text[i] == '{':depth += 1
        elif text[i] == '}':depth -= 1
        i += 1
    if depth:raise RepairError("Unclosed switch: "+anchor)
    return open_brace, i-1

def add_cases(text: str, anchor: str, cases: dict, langpos: int) -> tuple[str,int]:
    opening, closing = switch_span(text,anchor)
    block=text[opening+1:closing]
    # Fail closed if the enum stage names differ: no assumptions about API evolution.
    observed=set(re.findall(r'\(\s*\.english\s*,\s*\.(\w+)\s*\)',block)) if langpos==0 else set(re.findall(r'\(\s*\.(\w+)\s*,\s*\.english\s*\)',block))
    if set(cases) != observed:
        raise RepairError(f"Stage mismatch in {anchor}: expected {sorted(cases)}, found {sorted(observed)}")
    additions=[]
    for lang in LANGS:
        for stage, localized in cases.items():
            pair=f"(.{lang}, .{stage})" if langpos==0 else f"(.{stage}, .{lang})"
            if re.search(re.escape(pair)+r'\s*:',block):continue
            # Cases grouped with others via comma are also already covered.
            if re.search(re.escape(pair)+r'\s*[,\:]',block):continue
            txt=localized[lang].replace('\\','\\\\').replace('"','\\"')
            additions.append(f'        case {pair}: return "{txt}"')
    if not additions: return text,0
    return text[:closing]+"\n".join(additions)+"\n        "+text[closing:],len(additions)

def run(apply: bool):
    patches={}
    root=ROOT/'Sources/Views/RootView.swift'
    if not root.is_file():raise RepairError('Missing RootView.swift')
    raw=root.read_text('utf-8')
    desired='            .environment(\\.layoutDirection, settings.language.isRightToLeft ? .rightToLeft : .leftToRight)'
    if desired not in raw:
        point='            .preferredColorScheme(settings.appearance.colorScheme)'
        if raw.count(point)!=1:raise RepairError('RTL insertion point not found exactly once')
        changed=raw.replace(point,point+'\n'+desired,1)
        patches[root]=(raw,changed)
    total=0
    for relative,anchor,cases,pos in SPEC:
        p=ROOT/relative
        if not p.is_file():raise RepairError('Missing '+relative)
        before, curr=p.read_text('utf-8'),p.read_text('utf-8')
        if p in patches:curr=patches[p][1]
        curr,n=add_cases(curr,anchor,cases,pos)
        total+=n
        if curr!=before:patches[p]=(before,curr)
    print(f'VALIDATION: {len(patches)} source files, {total} missing language cases, RTL: {root in patches}')
    for path,(before,after) in patches.items():
        print(f' - {path.relative_to(ROOT)}: +{after.count(chr(10))-before.count(chr(10))} lines')
    if apply:
        for path,(_,after) in patches.items():path.write_text(after,'utf-8')
        print('APPLIED; run language audit, swiftc parsing and Xcode build next.')
    else:print('CHECK ONLY: repository unchanged. Use --apply after reviewing.')

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    group=parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--check',action='store_true')
    group.add_argument('--apply',action='store_true')
    args=parser.parse_args()
    try:run(args.apply)
    except (RepairError,OSError) as e:
        print('STOP: '+str(e));raise SystemExit(2)
