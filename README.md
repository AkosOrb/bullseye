# Bullseye – lőlap-kiértékelő app

Fotó alapján felismeri a találatokat egy lőlapon, kiszámolja a pontszámot,
és bejelöli a lövéseket. Első támogatott formátum: **MDLSz gyorspont lőlap**
(1–13 pont, 4,5 mm-es diabolo).

## Felépítés

| Mappa | Tartalom |
|---|---|
| `engine/` | Felismerő motor Pythonban (OpenCV). Ezen fejlesztjük és mérjük az algoritmust. |
| `engine/targets/` | Lőlap-formátumok leírása JSON-ban (új formátum = új fájl). |
| `testdata/` | Tesztfotók és a kézi (nézőkés) kiértékelés (`ground_truth.json`). |
| `app/` | A mobilapp (Flutter, Android és iOS). A motor Dartban, a telefonon fut, internet nélkül. |
| `app/tool/screens/` | Képernyőképek az appról (tesztből generálva). |

## Az app kipróbálása

### Android – a legegyszerűbb út (nem kell semmit telepíteni a gépre)

1. Minden feltöltés után a GitHub automatikusan elkészíti a telepítőt: a repó
   **Actions** fülén nyisd meg a legfrissebb zöld „Android APK” futást, és lent az
   **Artifacts** résznél töltsd le a `lolap-kiertekelo-apk` csomagot.
2. A zip-ből kibontott `app-release.apk`-t másold a telefonra, és nyisd meg.
   A telefon rákérdez, hogy engedélyezed-e az ismeretlen forrásból való telepítést: engedélyezd.

### iPhone (és bármilyen telefon) – webes változat

Nyisd meg Safariban: **https://akosorb.github.io/bullseye/**, majd a Megosztás gombbal
válaszd a **„Főképernyőhöz adás”** lehetőséget. Így ikonnal indul, mint egy app.
Az adatok a telefonon, a böngésző tárolójában maradnak. Minden feltöltés után
automatikusan frissül (`.github/workflows/web.yml`).

### Android vagy iOS – saját gépről

1. Telepítsd a [Flutter SDK-t](https://docs.flutter.dev/get-started/install) és az Android Studiót.
2. Csatlakoztasd a telefont USB-vel (Androidon a fejlesztői mód és az USB-hibakeresés kell).
3. ```bash
   cd app
   flutter pub get
   flutter run --release
   ```

**iOS-hez Mac kell** (Xcode-dal), vagy egy felhős építőszolgáltatás, például a
[Codemagic](https://codemagic.io), ami Mac nélkül is elkészíti és a TestFlightra tölti az appot.
Mindkettőhöz Apple fejlesztői fiók szükséges.

### Az app használata

1. **Lap fotózása**: a lőlapot egyenesen, árnyékmentesen, a keretbe igazítva fotózd le
   (vagy válassz képet a galériából).
2. Az app bejelöli a lövéseket („sorszám: pont”), fent látod az összpontszámot.
   A **sárga, szaggatott karikás** lövéseket érdemes nézőkével ellenőrizni.
3. Koppints egy lövésre: a pontszám a ± gombokkal felülírható, a jelölés húzással
   áthelyezhető, a kuka gombbal törölhető. Üres helyre koppintva új lövést adsz hozzá.
   Ha a talált lövések száma eltér a beállítottól, az app figyelmeztet.
4. Egy nap lapjai egy edzésbe kerülnek. Az edzés és a **Statisztika** oldal mutatja az
   átlagot, a fejlődést és a találati kép eltolódását; PDF-ben vagy képként megosztható.
5. A **Beállítások**ban állítható a lövésszám, a vonalérintés szabálya és a határeset-tűréshatár.

### Fejlesztőknek

```bash
cd app
flutter analyze
flutter test                                        # motor + felület tesztek
flutter test tool/screenshots_test.dart --update-goldens   # képernyőképek újragenerálása
```

Beépített betűtípusok: Space Grotesk (felület) és Noto Sans (PDF), mindkettő SIL Open Font License 1.1.

## A motor kipróbálása

```bash
cd engine
pip install -r requirements.txt
python -m bullseye_engine ../testdata/1_eredeti.png --shots 15 --out out
python tools/evaluate.py --out out     # összevetés a kézi eredményekkel
python -m pytest -q tests
```

## Pontosság a tesztfotókon

| Fotó | Gép | Kézi | Eltérés | Eltérő lövés (jelölve?) |
|---|---|---|---|---|
| 1 | 145 | 144 | +1 | 1 (igen) |
| 2 | 136 | 136 | 0 | 0 |
| 3 | 136 | 137 | −1 | 1 (igen) |

45 lövésből 45-öt megtalált a helyén, 43 pontszáma egyezik a kézivel, a két
eltérő lövés „nézőkével ellenőrizendő” jelzést kapott. Elfogadási feltétel
(±1 pont, minden bizonytalan lövés jelölve): **teljesül**.

## Az algoritmus röviden

1. **Kalibrálás** – a fekete korong szélére robusztus (RANSAC) ellipszist
   illesztünk, ebből affin transzformációval kiegyenesítjük a képet. Ezután
   minden gyűrűvonalat (13, 12, fehér korong széle, 10–7, fekete korong széle,
   külső vonalak) sugárirányú profilokkal megkeresünk, és robusztus
   körillesztéssel kapjuk a középpontjukat és sugarukat. A pontozás ezekhez a
   mért körökhöz történik, így a maradék perspektíva és a nyomdai eltérés sem
   rontja.
2. **Találatkeresés** – a lőlap forgásszimmetrikus, ezért sugáronként
   (szögszektoronként) háttérmodellt becslünk. Fekete területen a világosabb,
   fehér területen az ólomgyűrű miatt sötétebb foltok a találatok. A
   számfeliratokat a túloldali „ikerpárjukkal” vetjük össze, így nem okoznak
   hamis találatot.
3. **Egymásba lőtt lyukak** – a foltok területe és k-means lefedése alapján,
   a megadott lövésszámot is figyelembe véve bontjuk szét őket.
4. **Pontozás** – (középpont távolsága − lövedéksugár) ≤ gyűrűsugár; a
   gyűrűvonal a magasabb gyűrűhöz tartozik.
5. **Jelzések** – ha egy lövés 1,5 mm-en belül van a magasabb gyűrűtől, vagy
   alig érinti a sajátját, illetve ha szétbontásból származik, „ellenőrizendő”.
