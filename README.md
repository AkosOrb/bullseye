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
