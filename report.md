# Model check, 2026-10-26 17:20 UTC

19 forecast runs stored (2026-10-23T20:00Z to 2026-10-26T17:00Z).
Errors are mean absolute differences to the nearest DWD station; bias > 0 means the model is too high.
"Light wrong" = how often wind and gusts alone would have given a different rowing light than measured.
Stations are on land, where wind is usually weaker than on the lake, so the ranking matters more than the numbers.

## All points, day 1

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 3380 | 2.0 | +0.3 | 3.7 | 1.2 | 43 % |
| best_match | 3380 | 2.2 | +0.4 | 3.7 | 1.4 | 41 % |
| **icon_d2** (app today) | 3380 | 2.2 | +0.4 | 3.7 | 1.4 | 41 % |
| ecmwf_aifs025_single | 3380 | 2.2 | +0.6 | – | 1.0 | – |
| knmi_harmonie_arome_europe | 3380 | 2.4 | +0.9 | 3.9 | 1.2 | 44 % |
| ecmwf_ifs025 | 3380 | 2.4 | +1.2 | 3.8 | 1.1 | 50 % |
| dmi_harmonie_arome_europe | 3380 | 2.4 | +1.2 | 4.2 | 1.2 | 49 % |
| meteoswiss_icon_ch2 | 3380 | 2.6 | +1.3 | 4.3 | 1.7 | 47 % |
| meteoswiss_icon_ch1 | 3380 | 2.8 | +1.7 | 4.2 | 1.5 | 49 % |
| geosphere_arome_austria | 3380 | 2.9 | +1.7 | 4.0 | 1.6 | 46 % |

## All points, day 2

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 830 | 2.1 | +0.3 | 3.5 | 1.2 | 48 % |
| **icon_d2** (app today) | 820 | 2.2 | +0.6 | 3.6 | 1.4 | 47 % |
| best_match | 830 | 2.2 | +0.6 | 3.6 | 1.5 | 48 % |
| ecmwf_aifs025_single | 830 | 2.3 | +0.8 | – | 1.0 | – |
| knmi_harmonie_arome_europe | 830 | 2.4 | +1.0 | 3.7 | 1.1 | 49 % |
| meteoswiss_icon_ch1 | 430 | 2.4 | +1.7 | 2.9 | 1.5 | 43 % |
| dmi_harmonie_arome_europe | 830 | 2.4 | +1.2 | 3.9 | 1.2 | 50 % |
| ecmwf_ifs025 | 830 | 2.4 | +1.3 | 3.2 | 1.0 | 52 % |
| meteoswiss_icon_ch2 | 830 | 2.5 | +1.3 | 3.8 | 1.7 | 53 % |
| geosphere_arome_austria | 830 | 2.8 | +1.6 | 3.8 | 1.6 | 49 % |

## All points, archive

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 14385 | 0.8 | -0.0 | 1.7 | 1.2 | 10 % |
| **icon_d2** (app today) | 14385 | 0.9 | +0.2 | 1.6 | 1.4 | 9 % |
| best_match | 14385 | 0.9 | +0.2 | 1.6 | 1.4 | 9 % |
| ecmwf_aifs025_single | 14385 | 0.9 | +0.1 | – | 1.4 | – |
| knmi_harmonie_arome_europe | 14385 | 1.0 | +0.2 | 1.6 | 1.3 | 8 % |
| ecmwf_ifs025 | 14385 | 1.0 | +0.3 | 1.8 | 1.2 | 11 % |
| meteoswiss_icon_ch2 | 14385 | 1.0 | +0.4 | 2.0 | 1.5 | 12 % |
| dmi_harmonie_arome_europe | 14385 | 1.1 | +0.3 | 1.8 | 1.3 | 10 % |
| geosphere_arome_austria | 14385 | 1.1 | +0.4 | 1.6 | 1.7 | 10 % |
| meteoswiss_icon_ch1 | 14385 | 1.1 | +0.5 | 1.9 | 1.6 | 11 % |

## Once a day instead of twice?

Day 1 over all points, from the two scheduled runs (04:40 and 16:40 UTC) and from the 04:40 run alone.

| Model | Hours, twice | Hours, once | Wind error, twice | Wind error, once | Light wrong, twice | Light wrong, once |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 1780 | 200 | 2.03 | 2.34 | 39 % | 54 % |
| best_match | 1780 | 200 | 2.14 | 2.55 | 38 % | 50 % |
| icon_d2 | 1780 | 200 | 2.14 | 2.55 | 38 % | 50 % |
| ecmwf_aifs025_single | 1780 | 200 | 2.17 | 2.46 | – | – |
| knmi_harmonie_arome_europe | 1780 | 200 | 2.34 | 2.66 | 42 % | 53 % |
| ecmwf_ifs025 | 1780 | 200 | 2.37 | 2.74 | 47 % | 66 % |
| dmi_harmonie_arome_europe | 1780 | 200 | 2.38 | 2.74 | 47 % | 59 % |
| meteoswiss_icon_ch2 | 1780 | 200 | 2.56 | 2.88 | 45 % | 64 % |
| meteoswiss_icon_ch1 | 1780 | 200 | 2.78 | 3.21 | 47 % | 66 % |
| geosphere_arome_austria | 1780 | 200 | 2.86 | 3.27 | 44 % | 60 % |

Same order of the models with one run a day: **no** (twice: icon_eu, best_match, icon_d2; once: icon_eu, ecmwf_aifs025_single, best_match).

## icon_d2 vs best_match

120 forecast hours differ by more than wind 2.0 m/s, gusts 3.0 m/s or air 2.0 °C.

| Point | Hours |
| --- | --- |
| starnberger-see-south | 44 |
| staffelsee | 31 |
| starnberger-see-centre | 18 |
| tegernsee | 14 |
| kochelsee | 9 |
| tutzinger-rv | 3 |
| ammersee | 1 |

Latest:

| Run | Point | Hour | Differences |
| --- | --- | --- | --- |
| archive | staffelsee | 2026-10-03T00:00Z | temp +2.3 |
| archive | staffelsee | 2026-10-03T01:00Z | temp +2.2 |
| archive | staffelsee | 2026-10-04T00:00Z | temp -2.3 |
| archive | staffelsee | 2026-10-05T18:00Z | temp -2.1 |
| archive | staffelsee | 2026-10-07T00:00Z | temp -2.2 |
| archive | staffelsee | 2026-10-07T18:00Z | temp -2.4 |
| archive | staffelsee | 2026-10-12T18:00Z | temp -2.2 |
| archive | staffelsee | 2026-10-12T22:00Z | temp -2.2 |
| archive | staffelsee | 2026-10-13T04:00Z | temp -2.1 |
| archive | staffelsee | 2026-10-13T19:00Z | temp -2.1 |

## Per point (day 1)

### MRC 1880 launch point, Starnberg

Stations: wind: Wielenbach (Demollstr.) (19.0 km), gust: Wielenbach (Demollstr.) (19.0 km), temp: Attenkam (13.3 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 338 | 1.9 | +1.4 | 3.8 | 1.2 | 47 % |
| best_match | 338 | 1.9 | +1.5 | 2.6 | 1.4 | 31 % |
| **icon_d2** (app today) | 338 | 1.9 | +1.5 | 2.6 | 1.4 | 31 % |
| knmi_harmonie_arome_europe | 338 | 2.0 | +1.5 | 3.6 | 0.9 | 44 % |
| ecmwf_aifs025_single | 338 | 2.2 | +1.8 | – | 0.9 | – |
| dmi_harmonie_arome_europe | 338 | 2.4 | +2.1 | 3.4 | 1.1 | 43 % |
| meteoswiss_icon_ch2 | 338 | 2.4 | +2.2 | 3.2 | 1.4 | 34 % |
| ecmwf_ifs025 | 338 | 2.5 | +2.3 | 4.0 | 0.8 | 51 % |
| meteoswiss_icon_ch1 | 338 | 2.6 | +2.3 | 4.1 | 1.4 | 49 % |
| geosphere_arome_austria | 338 | 2.7 | +2.4 | 3.7 | 1.5 | 37 % |

### Tutzinger RV launch point

Stations: wind: Wielenbach (Demollstr.) (8.9 km), gust: Wielenbach (Demollstr.) (8.9 km), temp: Attenkam (6.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 338 | 1.1 | +0.3 | 1.8 | 1.1 | 28 % |
| **icon_d2** (app today) | 338 | 1.1 | +0.3 | 1.8 | 1.1 | 28 % |
| icon_eu | 338 | 1.4 | +0.9 | 2.6 | 1.1 | 35 % |
| knmi_harmonie_arome_europe | 338 | 1.5 | +0.4 | 2.4 | 1.0 | 29 % |
| geosphere_arome_austria | 338 | 1.5 | +0.8 | 3.1 | 1.7 | 39 % |
| dmi_harmonie_arome_europe | 338 | 1.7 | +1.0 | 3.2 | 0.8 | 40 % |
| meteoswiss_icon_ch2 | 338 | 1.9 | +1.5 | 2.6 | 1.7 | 30 % |
| meteoswiss_icon_ch1 | 338 | 2.0 | +1.7 | 2.6 | 1.4 | 35 % |
| ecmwf_aifs025_single | 338 | 2.2 | +1.8 | – | 0.9 | – |
| ecmwf_ifs025 | 338 | 2.5 | +2.3 | 4.0 | 0.8 | 51 % |

### Starnberger See, centre

Stations: wind: Wielenbach (Demollstr.) (11.4 km), gust: Wielenbach (Demollstr.) (11.4 km), temp: Attenkam (5.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 338 | 1.7 | +1.3 | 2.1 | 1.2 | 34 % |
| best_match | 338 | 1.8 | +1.5 | 2.6 | 1.3 | 32 % |
| **icon_d2** (app today) | 338 | 1.8 | +1.5 | 2.6 | 1.3 | 32 % |
| ecmwf_aifs025_single | 338 | 2.2 | +1.8 | – | 0.9 | – |
| ecmwf_ifs025 | 338 | 2.5 | +2.3 | 4.0 | 0.8 | 51 % |
| knmi_harmonie_arome_europe | 338 | 2.5 | +2.2 | 3.9 | 1.2 | 46 % |
| meteoswiss_icon_ch2 | 338 | 2.5 | +2.4 | 4.0 | 1.8 | 46 % |
| dmi_harmonie_arome_europe | 338 | 2.8 | +2.7 | 4.6 | 1.3 | 51 % |
| geosphere_arome_austria | 338 | 3.1 | +3.1 | 3.3 | 1.5 | 38 % |
| meteoswiss_icon_ch1 | 338 | 4.1 | +4.0 | 3.8 | 1.3 | 50 % |

### Starnberger See, south near Seeshaupt

Stations: wind: Wielenbach (Demollstr.) (13.6 km), gust: Wielenbach (Demollstr.) (13.6 km), temp: Attenkam (5.6 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| best_match | 338 | 1.1 | +0.1 | 1.9 | 1.2 | 33 % |
| **icon_d2** (app today) | 338 | 1.1 | +0.1 | 1.9 | 1.2 | 33 % |
| icon_eu | 338 | 1.2 | -0.1 | 2.2 | 1.2 | 33 % |
| dmi_harmonie_arome_europe | 338 | 1.5 | +0.8 | 2.8 | 1.0 | 35 % |
| knmi_harmonie_arome_europe | 338 | 1.6 | +0.4 | 2.8 | 0.9 | 32 % |
| meteoswiss_icon_ch1 | 338 | 1.6 | +1.1 | 2.5 | 1.3 | 34 % |
| ecmwf_aifs025_single | 338 | 1.7 | +0.4 | – | 0.8 | – |
| ecmwf_ifs025 | 338 | 1.9 | +1.0 | 3.4 | 1.1 | 52 % |
| geosphere_arome_austria | 338 | 2.4 | +2.3 | 2.4 | 1.6 | 32 % |
| meteoswiss_icon_ch2 | 338 | 2.4 | +2.2 | 3.4 | 2.2 | 48 % |

### Ammersee, centre

Stations: wind: Wielenbach (Demollstr.) (13.3 km), gust: Wielenbach (Demollstr.) (13.3 km), temp: Wielenbach (Demollstr.) (13.3 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_aifs025_single | 338 | 2.7 | +2.4 | – | 1.7 | – |
| icon_eu | 338 | 2.7 | +2.4 | 3.8 | 1.7 | 46 % |
| best_match | 338 | 2.8 | +2.6 | 3.1 | 1.7 | 38 % |
| **icon_d2** (app today) | 338 | 2.8 | +2.6 | 3.1 | 1.7 | 38 % |
| meteoswiss_icon_ch2 | 338 | 2.8 | +2.6 | 4.5 | 1.7 | 49 % |
| dmi_harmonie_arome_europe | 338 | 3.0 | +2.7 | 6.4 | 2.0 | 62 % |
| ecmwf_ifs025 | 338 | 3.1 | +3.0 | 4.8 | 1.4 | 60 % |
| knmi_harmonie_arome_europe | 338 | 3.6 | +3.5 | 5.5 | 2.1 | 56 % |
| meteoswiss_icon_ch1 | 338 | 4.2 | +4.1 | 4.0 | 2.2 | 52 % |
| geosphere_arome_austria | 338 | 5.1 | +5.1 | 5.4 | 1.8 | 55 % |

### Wörthsee, centre

Stations: wind: Wielenbach (Demollstr.) (20.6 km), gust: Wielenbach (Demollstr.) (20.6 km), temp: Maisach-Galgen (15.7 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_aifs025_single | 338 | 2.2 | +1.8 | – | 0.7 | – |
| ecmwf_ifs025 | 338 | 2.5 | +2.3 | 4.0 | 1.1 | 51 % |
| best_match | 338 | 2.5 | +2.2 | 3.1 | 1.1 | 37 % |
| **icon_d2** (app today) | 338 | 2.5 | +2.2 | 3.1 | 1.1 | 37 % |
| knmi_harmonie_arome_europe | 338 | 2.6 | +2.4 | 4.1 | 0.9 | 44 % |
| icon_eu | 338 | 2.7 | +2.3 | 4.3 | 1.0 | 49 % |
| meteoswiss_icon_ch2 | 338 | 3.1 | +2.9 | 4.4 | 0.7 | 50 % |
| meteoswiss_icon_ch1 | 338 | 3.3 | +3.1 | 4.6 | 0.9 | 50 % |
| dmi_harmonie_arome_europe | 338 | 3.3 | +3.2 | 4.4 | 0.8 | 48 % |
| geosphere_arome_austria | 338 | 3.4 | +3.2 | 5.4 | 0.8 | 51 % |

### Tegernsee, centre

Stations: wind: Kreuth (9.0 km), gust: Bichl (25.7 km), temp: Kreuth (9.0 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_aifs025_single | 338 | 1.3 | +1.2 | – | 1.3 | – |
| icon_eu | 338 | 1.4 | +1.0 | 6.1 | 0.9 | 58 % |
| dmi_harmonie_arome_europe | 338 | 2.4 | +2.4 | 5.0 | 1.1 | 55 % |
| best_match | 338 | 2.7 | +2.6 | 8.7 | 1.2 | 79 % |
| **icon_d2** (app today) | 338 | 2.7 | +2.6 | 8.7 | 1.2 | 79 % |
| ecmwf_ifs025 | 338 | 2.7 | +2.7 | 3.9 | 1.8 | 48 % |
| knmi_harmonie_arome_europe | 338 | 2.7 | +2.7 | 5.2 | 1.0 | 55 % |
| geosphere_arome_austria | 338 | 2.7 | +2.4 | 4.5 | 1.6 | 48 % |
| meteoswiss_icon_ch2 | 338 | 3.3 | +3.3 | 8.7 | 1.1 | 78 % |
| meteoswiss_icon_ch1 | 338 | 3.7 | +3.7 | 9.5 | 1.2 | 79 % |

### Kochelsee, centre

Stations: wind: Bichl (8.9 km), gust: Bichl (8.9 km), temp: Bichl (8.9 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| ecmwf_ifs025 | 338 | 1.2 | -0.0 | 1.9 | 1.6 | 29 % |
| ecmwf_aifs025_single | 338 | 1.4 | -0.6 | – | 1.3 | – |
| meteoswiss_icon_ch2 | 338 | 1.5 | -0.2 | 2.9 | 2.2 | 38 % |
| knmi_harmonie_arome_europe | 338 | 1.6 | -0.1 | 2.5 | 1.2 | 39 % |
| best_match | 338 | 1.7 | -1.1 | 2.7 | 1.5 | 35 % |
| **icon_d2** (app today) | 338 | 1.7 | -1.1 | 2.7 | 1.5 | 35 % |
| geosphere_arome_austria | 338 | 1.7 | -0.2 | 3.3 | 2.0 | 52 % |
| dmi_harmonie_arome_europe | 338 | 1.7 | +0.4 | 3.0 | 1.4 | 54 % |
| meteoswiss_icon_ch1 | 338 | 1.8 | -0.3 | 3.0 | 1.4 | 53 % |
| icon_eu | 338 | 1.8 | -1.3 | 2.5 | 0.9 | 37 % |

### Staffelsee, centre

Stations: wind: Hohenpeißenberg (16.9 km), gust: Hohenpeißenberg (16.9 km), temp: Kohlgrub, Bad (Rosshof) (7.4 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| meteoswiss_icon_ch1 | 338 | 3.7 | -3.6 | 5.7 | 2.6 | 51 % |
| dmi_harmonie_arome_europe | 338 | 4.2 | -4.1 | 7.2 | 1.6 | 69 % |
| geosphere_arome_austria | 338 | 4.3 | -4.2 | 6.9 | 2.3 | 67 % |
| ecmwf_ifs025 | 338 | 4.4 | -4.4 | 6.8 | 1.0 | 69 % |
| meteoswiss_icon_ch2 | 338 | 4.5 | -4.5 | 7.2 | 2.8 | 64 % |
| knmi_harmonie_arome_europe | 338 | 4.6 | -4.5 | 7.2 | 1.4 | 64 % |
| icon_eu | 338 | 4.9 | -4.9 | 8.5 | 1.7 | 75 % |
| ecmwf_aifs025_single | 338 | 5.0 | -5.0 | – | 0.9 | – |
| **icon_d2** (app today) | 338 | 5.4 | -5.4 | 9.1 | 2.7 | 71 % |
| best_match | 338 | 5.4 | -5.4 | 9.1 | 2.7 | 72 % |

### Olympic regatta course Oberschleißheim

Stations: wind: München-Stadt (9.2 km), gust: München-Stadt (9.2 km), temp: München-Stadt (9.2 km)

| Model | Hours | Wind error m/s | Wind bias | Gust error m/s | Air temp error °C | Light wrong |
| --- | --- | --- | --- | --- | --- | --- |
| icon_eu | 338 | 0.8 | +0.3 | 1.2 | 0.7 | 18 % |
| best_match | 338 | 0.8 | +0.2 | 1.6 | 0.7 | 26 % |
| **icon_d2** (app today) | 338 | 0.8 | +0.2 | 1.6 | 0.7 | 26 % |
| ecmwf_ifs025 | 338 | 1.1 | +0.9 | 1.8 | 0.9 | 34 % |
| ecmwf_aifs025_single | 338 | 1.1 | +0.8 | – | 0.8 | – |
| knmi_harmonie_arome_europe | 338 | 1.1 | +0.8 | 2.1 | 1.0 | 31 % |
| meteoswiss_icon_ch2 | 338 | 1.1 | +0.7 | 1.9 | 0.8 | 35 % |
| dmi_harmonie_arome_europe | 338 | 1.2 | +0.9 | 2.1 | 1.0 | 35 % |
| meteoswiss_icon_ch1 | 338 | 1.3 | +1.1 | 2.3 | 1.0 | 38 % |
| geosphere_arome_austria | 338 | 2.1 | +2.0 | 2.5 | 1.3 | 36 % |

Data: Open-Meteo; measurements Deutscher Wetterdienst (CC BY 4.0).
