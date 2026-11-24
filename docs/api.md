# Alusekis API v1

Serveris: `server/` (ASP.NET Core, `Alusekis.Api`). Šis dokumentas – sutartis tarp serverio ir mobiliosios programėlės.

**Būsena:** ✅ įgyvendinta · 🕓 suplanuota (T0 sukurtas tik karkasas; endpoint'ų formos gali dar keistis, kol neįgyvendinti).

## Bendros taisyklės

| Tema | Taisyklė |
|---|---|
| Bazinis kelias | `/api/v1` (išskyrus `GET /health`) |
| Formatas | JSON, `Content-Type: application/json; charset=utf-8`, laukai `camelCase` |
| Datos | UTC, ISO 8601 su `Z`, pvz. `2026-11-20T18:30:00Z` |
| Kainos | sveiki centai `priceCents`, 1–50000 (0,01–500,00 €) |
| Talpa | sveiki mililitrai `volumeMl`, 1–50000 |
| ID | `long` (64 bitų sveikas skaičius) |
| Enum'ai | eilutės: `Role` = `Guest`/`User`/`Admin`; `PriceStatus` = `Pending`/`Approved`/`Rejected`; `ReportReason` = `WrongPrice`/`DifferentProduct`/`OutdatedData`/`Other`; `ReportStatus` = `New`/`Confirmed`/`Rejected` |
| Autentifikacija | `Authorization: Bearer <token>` (✅) |
| Idempotentiškumas | rašymo užklausoms `Idempotency-Key: <uuid>`; pakartota užklausa su tuo pačiu raktu grąžina pirminį atsakymą (🕓) |
| Užklausos ID | `X-Request-Id` grąžinamas kiekviename atsakyme; klientas gali atsiųsti savo (iki 64 simb., `A-Z a-z 0-9 - _ . :`) |
| Laiko limitas | serveris užklausą apdoroja ne ilgiau kaip 10 s, kitaip `504 request_timeout` |

### Klaidos

Visos klaidos turi vienodą formą:

```json
{
  "code": "not_found",
  "message": "The requested resource was not found.",
  "requestId": "0HNQ98LI8J140:00000002"
}
```

| HTTP | `code` |
|---|---|
| 400 | `bad_request` |
| 401 | `unauthorized` |
| 403 | `forbidden` |
| 404 | `not_found` |
| 405 | `method_not_allowed` |
| 409 | `conflict` (registracijai – `email_taken`) |
| 422 | `validation_failed` (autentifikacijai – `email_invalid`, `password_length_invalid`) |
| 429 | `too_many_requests` |
| 500 | `internal_error` |
| 503 | `service_unavailable` |
| 504 | `request_timeout` |

---

## Sistema

### ✅ `GET /health`
Serverio ir DB būsena. `200` – sveika, `503` – ne.

```json
{
  "status": "Healthy",
  "checks": {
    "server": { "status": "Healthy", "description": null },
    "database": { "status": "Healthy", "description": "Database is reachable and up to date." }
  },
  "checkedAt": "2026-11-23T09:38:45.4659974Z"
}
```

### ✅ `GET /api/v1/ping`
```json
{ "status": "ok", "serverTime": "2026-11-23T09:37:29.9521625Z" }
```

---

## ✅ Autentifikacija (NI-01)

Prieigos raktas – atsitiktinis 256 bitų raktas, DB saugoma tik jo SHA-256 maiša. Galioja **30 min.** nuo išdavimo (be pratęsimo); serveris kiekvienoje autentifikuotoje užklausoje tikrina sesiją DB. Slaptažodžiai – `PasswordHasher<User>` (PBKDF2 + druska). Rolės: `Guest` (neprisijungęs, tik peržiūra), `User` (keičia duomenis), `Admin` (valdo katalogą) – tikrinamos tik serveryje (policy `RequireUser`, `RequireAdmin`).

Nauji klaidų kodai: `email_invalid` (422), `email_taken` (409), `password_length_invalid` (422), `invalid_credentials` (401), `invalid_password` (403), `invalid_reset_token` (400). Visada grąžinamas vienas kodas (pirmas rastas: el. paštas, tada slaptažodis).

### `POST /api/v1/auth/register`
```json
// užklausa: el. paštas ≤ 254 simb., slaptažodis 12–128 simb.
{ "email": "jonas@example.com", "password": "********" }
```
```json
// 201
{
  "user": { "id": 2, "email": "jonas@example.com", "displayName": "jonas", "role": "User" },
  "token": "<opaque>",
  "expiresAt": "2026-11-23T10:30:00Z"
}
```
`422 email_invalid` / `422 password_length_invalid`; `409 email_taken` – el. paštas (be didžiųjų raidžių ir tarpų skirtumo) jau užimtas.

### `POST /api/v1/auth/login`
```json
{ "email": "jonas@example.com", "password": "********" }
```
`200` – kaip registracijos. Bet kokia klaida (nėra paskyros / blogas slaptažodis) – vienodas `401 invalid_credentials`. Po 5 nesėkmingų bandymų vienai paskyrai per 15 min. – `429 too_many_requests` su `Retry-After` (sekundėmis), net jei slaptažodis teisingas.

### `POST /api/v1/auth/logout` (prisijungus)
Atšaukia šią sesiją (`RevokedAt`). `204`. Tas pats raktas toliau grąžina `401 unauthorized`.

### `GET /api/v1/auth/me` (prisijungus)
```json
{ "id": 2, "email": "jonas@example.com", "displayName": "jonas", "role": "User" }
```

### `POST /api/v1/auth/forgot-password`
```json
{ "email": "jonas@example.com" }
```
Visada `202` (neatskleidžia, ar paskyra yra); `422 email_invalid` tik blogam formatui. Sukuriamas vienkartinis raktas (galioja 30 min., DB – tik maiša) ir per `IEmailSender` išsiunčiama nuoroda `alusekis://reset-password?token=...`. Kol nėra SMTP, nuoroda išvedama į serverio žurnalą (`ConsoleEmailSender`).

### `POST /api/v1/auth/reset-password`
```json
{ "token": "<iš nuorodos>", "newPassword": "********" }
```
`204` – slaptažodis pakeistas, raktas panaudotas, visos sesijos atšauktos. `400 invalid_reset_token` – raktas neteisingas, pasibaigęs ar jau panaudotas; `422 password_length_invalid`.

### `DELETE /api/v1/auth/account` (prisijungus)
```json
{ "password": "********" }
```
`204` – paskyra ir sesijos ištrintos; kainos, produktai ir pranešimai lieka be nuorodos į asmenį; sukuriamas `DeletionMarker` (`User`, id) ir audito įrašas be asmens duomenų. Blogas slaptažodis – `403 invalid_password` (ne 401, kad klientas neatjungtų vartotojo); bandymai skaičiuojami į tą patį 5/15 min. limitą.

---

## Parduotuvės (NI-02: `cities`, `stores`; NI-03: `stores/{id}/prices`)

Prisijungti nereikia (leidžiama svečiui). Vietos duomenys naudojami tik vienai paieškai: nesaugomi ir nelogginami.

### ✅ `GET /api/v1/cities`
Miestų sąrašas pagal pavadinimą.
```json
{ "items": [ { "id": 2, "name": "Kaunas" }, { "id": 3, "name": "Klaipėda" }, { "id": 1, "name": "Vilnius" } ] }
```

### ✅ `GET /api/v1/stores`
Vienas iš dviejų režimų:

| Režimas | Parametrai | Rikiavimas |
|---|---|---|
| Netoliese | `lat` (−90…90), `lng` (−180…180), `radiusKm` (sveikas 1–50) – visi trys | pagal atstumą (Haversine), artimiausia pirma; yra `distanceKm` |
| Pagal miestą | `cityId` | pagal pavadinimą; `distanceKm` nėra |

Blogos reikšmės, abu režimai kartu, nė vieno ar ne visi trys GPS parametrai – `422 validation_failed`; neskaitomas skaičius (pvz. `lat=abc`) – `400 bad_request`. Parduotuvių nerasta (ar nezinomas `cityId`) – `200` su tuščiu `items`. Daugiausia 200 įrašų.
```json
{
  "items": [
    {
      "id": 2,
      "name": "Rimi Hyper",
      "address": "Ozo g. 25",
      "latitude": 54.7117,
      "longitude": 25.2827,
      "distanceKm": 3.67,
      "city": { "id": 1, "name": "Vilnius" }
    }
  ]
}
```
Seed koordinatės yra apytikslės (iki kvartalo tikslumo).

### ✅ `GET /api/v1/stores/{storeId}/prices?page=1&pageSize=20` (NI-03)
Naujausia **patvirtinta** (`Approved`) kiekvieno produkto kaina parduotuvėje: pagal `ObservedAt` mažėjančiai, tada `Id` mažėjančiai. `Pending` ir `Rejected` įrašai neimami (klaidingai pažymėtas naujesnis įrašas nepaslepia senesnės galiojančios kainos). Prisijungti nereikia.

| Parametras | Taisyklė |
|---|---|
| `page` | 1–100000, numatyta 1 |
| `pageSize` | 1–100, numatyta 20 |

Blogos reikšmės – `422 validation_failed`, neskaitomas skaičius – `400 bad_request`, nezinoma parduotuvė – `404 not_found`. Parduotuvė be kainų – `200` su tuščiu `items` ir `total: 0`. Rikiavimas stabilus: produkto pavadinimas (be diakritikų ir didžiųjų raidžių skirtumo), tada talpa.

`isStale` = `true`, kai `observedAt` senesnis nei 7 paros pagal **serverio** laikrodį (lygiai 7 paros – dar ne). Tai tik žyma, įrašas nekeičiamas.
```json
{
  "store": { "id": 1, "name": "Maxima XX", "address": "Ukmergės g. 282" },
  "items": [
    {
      "priceEntryId": 41,
      "productId": 1,
      "productName": "Švyturys Ekstra",
      "volumeMl": 500,
      "priceCents": 149,
      "observedAt": "2026-10-30T09:00:00Z",
      "isStale": true
    }
  ],
  "total": 1,
  "page": 1,
  "pageSize": 20
}
```

---

## Produktai (NI-04: `products/search` ✅, kita 🕓)

### ✅ `GET /api/v1/products/search?q=svyturys` (NI-04)
Prisijungti nereikia. `q` apkarpomas (trim) ir turi būti **2–100 simbolių**, kitaip `422 validation_failed` su klaidų DTO (trūkstamas, tuščias, 1 ar 101 simbolis).

Paieška pagal pavadinimo **dalį**, nejautri didžiosioms raidėms ir diakritikams: užklausa ir `Product.NormalizedName` normalizuojami ta pačia funkcija (mažosios raidės, be diakritikų, suspausti tarpai), todėl `žalgiris`, `ŽALGIRIS` ir `zalgiris` randa „Žalgiris“. Tekstas lyginamas pažodžiui (jokio LIKE), `%`, `_` ir `'` yra paprasti simboliai. Užklausa, kuri po normalizavimo tampa tuščia (vien jungiamieji ženklai), graužina tuščią sąrašą, ne visą katalogą.

Rikiavimas: pirma pavadinimai, kurie **prasideda** užklausa, tada pagal normalizuotą pavadinimą, tada talpą. Daugiausia **50** rezultatų. Nieko nerasta – `200` su tuščiu `items`.

`lowestPrice` (nebus, jei produktas kainų neturi) – pigiausia iš naujausių **patvirtintų** (`Approved`) kainų parduotuvėse (po vieną įrašą kiekvienoje parduotuvėje; senesnė pakeista kaina, `Rejected` ir `Pending` neskaitomi). `isStale` – `observedAt` senesnis nei 7 paros pagal serverio laikrodį. `brand` nebus, jei nėra.
```json
{
  "items": [
    {
      "id": 1,
      "name": "Švyturys Ekstra",
      "brand": "Švyturys",
      "volumeMl": 500,
      "lowestPrice": {
        "priceCents": 139,
        "storeId": 4,
        "storeName": "Lidl",
        "observedAt": "2026-10-28T15:00:00Z",
        "isStale": true
      }
    }
  ]
}
```

### `POST /api/v1/products` (prisijungus)
```json
// užklausa (+ Idempotency-Key)
{ "name": "Dundulis Kvietinis", "brand": "Dundulis", "volumeMl": 500 }
```
```json
// 201
{ "id": 31, "name": "Dundulis Kvietinis", "brand": "Dundulis", "volumeMl": 500, "createdAt": "2026-11-23T10:00:00Z" }
```
`409 conflict` – produktas su tuo pačiu normalizuotu pavadinimu ir talpa jau yra.

### ✅ `GET /api/v1/products/{productId}/prices?sort=asc|desc` (NI-05)
Palyginimas: to paties produkto naujausia **patvirtinta** (`Approved`) kaina **kiekvienoje parduotuvėje** (pagal `ObservedAt` mažėjančiai, tada `Id`). `Rejected` ir `Pending` įrašai neimami. Prisijungti nereikia. Anksčiau planuotas `.../compare` pakeistas šiuo endpoint'u.

Produkto tapatybė = ID + talpa: to paties pavadinimo kitos talpos produktas turi kitą ID ir niekada nemaišomas.

| Parametras | Taisyklė |
|---|---|
| `sort` | `asc` (numatyta, pigiausia pirma) arba `desc` (brangiausia pirma), nepriklauso nuo raidžių dydžio; kita – `422 validation_failed` |

Vienodos kainos visada rikiuojamos pagal `storeId` didėjančiai (ir `asc`, ir `desc`), todėl tvarka stabili. `isStale` = `true`, kai `observedAt` senesnis nei 7 paros pagal serverio laikrodį (lygiai 7 paros – dar ne). `storeCount` – kiek parduotuvių turi kainą; `singleStore` = `true`, kai tik viena (palyginti nėra su kuo, bet kaina vis tiek grąžinama).

Nėra kainų – `200` su tuščiu `items` ir `storeCount: 0`. Nezinomas (ar neskaitinis) `productId` – `404 not_found`.
```json
{
  "product": { "id": 1, "name": "Švyturys Ekstra", "brand": "Švyturys", "volumeMl": 500 },
  "items": [
    {
      "priceEntryId": 52,
      "storeId": 4,
      "storeName": "Lidl",
      "storeAddress": "Kalvarijų g. 202",
      "priceCents": 139,
      "observedAt": "2026-10-28T15:00:00Z",
      "isStale": true
    },
    {
      "priceEntryId": 41,
      "storeId": 1,
      "storeName": "Maxima XX",
      "storeAddress": "Ukmergės g. 282",
      "priceCents": 149,
      "observedAt": "2026-10-30T09:00:00Z",
      "isStale": true
    }
  ],
  "storeCount": 2,
  "singleStore": false
}
```

### ✅ `GET /api/v1/products/{productId}/stores/{storeId}/history?days=7|30|90` (NI-06)
Produkto kainų istorija **vienoje parduotuvėje**. Prisijungti nereikia. Anksčiau planuotas `.../history?storeId=` pakeistas šiuo endpoint'u. Istorija nekeičiama ir neeišgalvojama: vienas įrašas = vienas taškas, tarpinės kainos nekuriamos, ta pati kaina keliuose įrašuose lieka keliais taškais.

| Parametras | Taisyklė |
|---|---|
| `days` | tik tekstas `7`, `30` arba `90`; trūkstamas = `30`. Kita (`abc`, tuščias, `0`, `8`, `07`, `7.0`, `365`) – `422 validation_failed` |

Langas: įrašai, kurių `observedAt` ≥ `from`, kur `from` = serverio „dabar“ − `days` parų. Įrašas lygiai ties riba įtraukiamas, 1 sekundė anksčiau – ne. Imami tik **patvirtinti** (`Approved`) įrašai (`Rejected` ir `Pending` ne). Rikiavimas: nuo seniausio iki naujausio (`observedAt`, tada `priceEntryId`). `from` ir `to` (= serverio „dabar“) skirti grafiko ašiai.

Nezinomas produktas ar parduotuvė (ar neskaitinis ID) – `404 not_found`. Nėra įrašų per laikotarpį – `200` su tuščiu `items`. Kita parduotuvė ir kita to paties pavadinimo talpa (tai kitas produktas) nemaišomos.
```json
{
  "product": { "id": 1, "name": "Švyturys Ekstra", "brand": "Švyturys", "volumeMl": 500 },
  "store": { "id": 1, "name": "Maxima XX", "address": "Ukmergės g. 282" },
  "days": 30,
  "from": "2026-10-24T12:00:00Z",
  "to": "2026-11-23T12:00:00Z",
  "items": [
    { "priceEntryId": 17, "priceCents": 145, "observedAt": "2026-10-28T21:00:00Z" },
    { "priceEntryId": 41, "priceCents": 149, "observedAt": "2026-11-12T09:00:00Z" }
  ]
}
```

---

## Kainos (NI-07)

### ✅ `POST /api/v1/prices` (prisijungus: `User` arba `Admin`)
Patikrintos kainos pateikimas. Kainų istorija nekeičiama: kiekviena pateikta kaina yra **naujas** `PriceEntry`, ankstesni niekada neperrašomi. Laikas (`observedAt` = `createdAt`) imamas iš **serverio**, `submittedByUserId` – prisijungęs vartotojas, būsena iškart `Approved` (kad kiti matytų). Neprisijungęs – `401 unauthorized`, rolė `Guest` – `403 forbidden` (tikrinama tik serveryje).
```json
// užklausa
{ "productId": 1, "storeId": 1, "priceCents": 155, "idempotencyKey": "2b1f0c3e-...", "confirmLargeChange": false }
```
```json
// 201
{ "id": 61, "productId": 1, "storeId": 1, "priceCents": 155, "observedAt": "2026-11-24T08:46:02Z", "isLargeChange": false }
```

| Atvejis | Atsakymas |
|---|---|
| `priceCents` nėra ar už 1–50000 | `422 price_invalid` |
| `idempotencyKey` nėra, tuščias ar > 100 simb.; nėra `productId`/`storeId` | `422 validation_failed` |
| Nėra produkto ar parduotuvės | `404 not_found` |
| Daugiau nei 50 % nuo ankstesnės galiojančios (`Approved`) šios poros kainos ir be `confirmLargeChange: true` | `409 large_price_change` su `previousPriceCents` (žr. žemiau) |
| Tas pats `idempotencyKey` (tam pačiam vartotojui) su **tuo pačiu** turiniu | grąžinamas pirminis atsakymas (tas pats statusas ir JSON), antraštė `Idempotency-Replayed: true`, nieko naujo nesukuriama |
| Tas pats `idempotencyKey` su **kitu** turiniu (`productId`, `storeId`, `priceCents`, `confirmLargeChange`) | `409 idempotency_key_reused` |

Didelio skirtumo taisyklė (FR-08), sveikaisiais skaičiais: `abs(nauja − sena) * 100 > sena * 50`. Lygiai 50 % – dar leidžiama. Jei ankstesnės kainos nėra, tikrinimo nėra. Patvirtinus įrašas sukuriamas su `isLargeChange: true`.
```json
// 409
{ "code": "large_price_change", "message": "...", "requestId": "...", "previousPriceCents": 149 }
```

Nesėkmingi atsakymai nesaugomi, todėl po `409 large_price_change` tas pats raktas gali būti naudojamas su `confirmLargeChange: true`. `PriceEntry`, audito įrašas (`PriceSubmitted`, be raktų ir slaptažodžių) ir išsaugotas atsakymas rašomi **vienoje transakcijoje**: bet kokia klaida – nieko neišsaugoma.

---

## Pranešimai apie klaidas 🕓

### `POST /api/v1/reports` (prisijungus)
```json
// užklausa (+ Idempotency-Key)
{ "priceEntryId": 41, "reason": "OutdatedData", "comment": "Kaina jau 1,69 €" }
```
```json
// 201
{ "id": 7, "priceEntryId": 41, "reason": "OutdatedData", "status": "New", "submittedAt": "2026-11-23T09:10:00Z" }
```

### `GET /api/v1/reports?status=New&limit=50` (Admin)
```json
{
  "items": [
    {
      "id": 7,
      "priceEntryId": 41,
      "reason": "OutdatedData",
      "comment": "Kaina jau 1,69 €",
      "status": "New",
      "reporterUserId": 2,
      "submittedAt": "2026-11-23T09:10:00Z"
    }
  ]
}
```

### `PATCH /api/v1/reports/{reportId}` (Admin)
```json
// užklausa
{ "status": "Confirmed" }
```
```json
// 200
{ "id": 7, "status": "Confirmed", "resolvedAt": "2026-11-23T11:00:00Z", "resolvedByUserId": 1 }
```

---

## Vietinis paleidimas

```bash
cd server
dotnet run --project src/Alusekis.Api            # Development: SQLite failas, auto-migracija
dotnet run --project src/Alusekis.Api -- seed    # bandomieji duomenys (pakartotinai saugu)
dotnet test
```

Konfigūracija – `appsettings*.json`, perrašoma aplinkos kintamaisiais:

| Nustatymas | Aplinkos kintamasis | Būtinas |
|---|---|---|
| `ConnectionStrings:Default` | `ConnectionStrings__Default` | taip – be jo serveris nepasileidžia |
| `Database:MigrateOnStartup` | `Database__MigrateOnStartup` | ne (numatyta `false`, Development – `true`) |

Bandomoji paskyra po seed: `test@alusekis.local` (rolė `User`, slaptažodis nenustatytas – prisijungti negalima; norint turėti paskyrą su slaptažodžiu, užsiregistruokite arba pasinaudokite `forgot-password`, nuoroda bus serverio žurnale).
