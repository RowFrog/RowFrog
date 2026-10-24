"""The parsing in the club import scripts (scripts/), without network."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

import club_import  # noqa: E402
import import_oerv  # noqa: E402
import import_swissrowing  # noqa: E402


def test_addresses_split_into_street_postcode_and_town():
    assert club_import.split_address("An der unteren Alten Donau 21, 1220 Wien", 4) == ("An der unteren Alten Donau 21", "1220", "Wien")
    assert club_import.split_address("CH-6060 Sarnen", 4) == ("", "6060", "Sarnen")
    assert club_import.split_address("Seestrasse 1, 8810 Horgen ZH", 4) == ("Seestrasse 1", "8810", "Horgen ZH")
    assert club_import.split_address("Wien", 4) is None


def test_oerv_list_is_read_from_the_page_script():
    page = '''<script>oerv_vereine_data=[{"land":"wien","name":"Vereine in Wien","vereine":[
        {"name":"Wiener Ruderklub Argonauten","short":"ARG","url":"https:\\/\\/www.argowien.at\\/",
         "email":"office@argowien.at","address":"An der unteren Alten Donau 21, 1220 Wien","cert_nada":0}]},
        {"land":"kaernten","name":"Vereine in K\\u00e4rnten","vereine":[]}];
        function x() { return [1]; }</script>'''
    states = import_oerv.club_list(page)
    assert [import_oerv.state_name(s) for s in states] == ["Wien", "Kärnten"]
    assert states[0]["vereine"][0]["url"] == "https://www.argowien.at/"


def test_swiss_rowing_directory_and_club_page():
    listing = '''<td class="views-field views-field-title"><a href="/de/club/basler-ruder-club" hreflang="de">Basler Ruder-Club</a></td>
        <td class="views-field views-field-title"><a href="/de/node/501" hreflang="de">Belvoir Ruderclub Z&uuml;rich</a></td>'''
    assert import_swissrowing.club_links(listing) == [
        ("https://www.swissrowing.ch/de/club/basler-ruder-club", "Basler Ruder-Club"),
        ("https://www.swissrowing.ch/de/node/501", "Belvoir Ruderclub Zürich"),
    ]
    page = '''<main><h1>Ruder-Club Thun</h1><p>Gegründet 1883</p><p>Ruder-Club Thun<br>Seestrasse 22<br>3600 Thun</p>
        <a href="https://www.rcthun.ch">Website</a><a href="https://www.facebook.com/rct">fb</a></main>'''
    club = import_swissrowing.parse_club("u", "Ruder-Club Thun", page)
    assert club["_parts"] == ("Seestrasse 22", "3600", "Thun")
    assert club["founded"] == 1883
    assert club["website"] == "https://www.rcthun.ch"
    assert club["address"] == "Seestrasse 22, 3600 Thun"
