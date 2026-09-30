/// Password managers' browser extensions, by the ID Chromium gives them.
///
/// Browsers give their extensions no way to mark a copy as secret, so a password copied
/// from one of these arrives without the marker a password manager's desktop app sets.
/// Chromium does record where a copy made by a web page or an extension page came from,
/// as `org.chromium.source-url`, and for a copy made on the extension's own pages — its
/// popup, side panel, a tab of its own, or its offscreen document — that is
/// `chrome-extension://<id>/…`. The ID is what recognises the secret.
///
/// A list, not every extension: some extensions that are not password managers show
/// ordinary text on pages of their own. Adobe Acrobat's, with hundreds of millions of
/// users, shows PDFs on a `chrome-extension://` page, so copying from a PDF would have
/// counted as copying a secret.
///
/// Each store publishes its own package with its own ID, so a product has one ID per store
/// it is in, and some have beta channels; the store is named beside each ID. They were
/// looked up on 2026-09-30, and how is in PLAN.md, *Secrets copied from a browser
/// extension*. Four have no store listing and are kept on the strength of the vendor's own
/// files; they say so.
///
/// Keep it to password managers. A match marks a copy secret, which shows it as dots and
/// keeps it off disk even when pinned — and since a secret mark sticks when identical
/// entries merge, a match can also take an entry that was pinned earlier off disk.
enum PasswordManagerExtensions {
    static let ids: Set<String> = [
        // Bitwarden
        "nngceckbapebfimnlniiiahkandclblb",  // Chrome Web Store
        "hccnnhgbibccigepcmlgppchkpfdophk",  // Chrome Web Store, beta
        "jbkfoedolllekgbhcbcoahefnbanhhlh",  // Edge Add-ons
        "ccnckbpmaceehanjmeomladnmlffdjgn",  // Opera add-ons
        // 1Password
        "aeblfdkhhhdcdjpifhhbdiojplfjncoa",  // Chrome Web Store
        "khgocmkkpikpnmmkgmdnfckapcdkgfaf",  // Chrome Web Store, beta
        "gejiddohjgogedgjnonbofjigllpkmbf",  // Chrome Web Store, nightly
        "dppgmdbiimibapkepcbdbmkaabgiofem",  // Edge Add-ons
        "aomjjhallfgjeglblehebfpbcfeobpgk",  // Chrome Web Store, the classic extension: delisted
        "hjlinigoblmkhjejkmbegnoaljkphmgo",  // no listing: 1Password's native-messaging host accepts it
        "bkpbhnjcbehoklfkljkkbbmipaphipgl",  // no listing: 1Password's native-messaging host accepts it
        // LastPass
        "hdokiejnpimakedhajhdlcegeplioahd",  // Chrome Web Store
        "bbcinlkgjjkejfdpemiealijmmooekmp",  // Edge Add-ons
        "hnjalnkldgigidggphhmacmimbdlafdo",  // Opera add-ons
        // Dashlane
        "fdjamakpfbbddfjaooikfcpapjohcfmg",  // Chrome Web Store
        "gehmmocbbkpblljhkekmfhjpfbkclbph",  // Edge Add-ons
        // Keeper
        "bfogiafebfohielmmehodmfbbebbbpei",  // Chrome Web Store
        "kbedblbpfmeicfpadihimgombbafaeeh",  // Chrome Web Store, second listing
        "lfochlioelphaglamdcakfjemolpichk",  // Edge Add-ons
        "mpfckamfocjknfipmpjdkkebpnieooca",  // Edge Add-ons, second listing
        // NordPass
        "eiaeiblijfjekdanodkjadfinkhbfgcd",  // Chrome Web Store
        "fooolghllnmhmmndgjiamiiodkpenpbb",  // Chrome Web Store, its legacy listing, same build
        "oakginmjipboeflcgnbipnjojnpchnpd",  // Edge Add-ons
        // Proton Pass
        "ghmbeldphafepmbegfdlkpapadhbakde",  // Chrome Web Store
        "hlaiofkbmjenhgeinjlmkafaipackfjh",  // Chrome Web Store, beta
        "gcllgfdnfnllodcaambdaknbipemelie",  // Edge Add-ons
        // KeePassXC-Browser
        "oboonakemofpalcgghocfoadofidjkkk",  // Chrome Web Store
        "pdffhmdngciaglkoonimfcmckehcpafo",  // Edge Add-ons
        // Enpass
        "kmcfomidfpdkfieipokbalgegidffkal",  // Chrome Web Store
        "mliehcloacfoicbanjhhnlimealolgoi",  // Edge Add-ons
        // RoboForm
        "pnlccmojcmeohlpggmfnbbiapkmbliob",  // Chrome Web Store
        "ljfpcifpgbbchoddpjefaipoiigpdmag",  // Edge Add-ons
        // Devolutions Password Manager, formerly Devolutions Web Login
        "neimonjjffhehnojilepgfejkneaidmo",  // Chrome Web Store
        "ddloeodolhdfbohkokiflfbacbfpjahp",  // Edge Add-ons
        "pbgddncilcopdjinhhijbopkihcnhmed",  // no listing: the Opera ID Remote Desktop Manager has built in
        // Apple iCloud Passwords
        "pejdijmoenmkgeppbflobdenhhabjlaj",  // Chrome Web Store
        "mfbcdcnpokpoajjciilocoachedjkima",  // Edge Add-ons
        // Zoho Vault
        "igkpcodhieompeloncfnbekccinhapdb",  // Chrome Web Store
        "aomonpiegmnimnhlnpjkoinpiopofgkc",  // Edge Add-ons
        // Passbolt
        "didegimhafipceonhjepacocaffmoppf",  // Chrome Web Store
        "ljeppgjhohmhpbdhjjjbiflabdgfkhpo",  // Edge Add-ons
        // Sticky Password
        "bnfdmghkeppfadphbnkjcicejfepnbfe",  // Chrome Web Store
        "jbipmfkjgjhibkepepeneigpkfeikikp",  // Edge Add-ons
        // Norton Password Manager
        "admmjipmmciaobhojoghlmleefbicajg",  // Chrome Web Store
        "lcccdlklhahfmobgpnilndimkankpnkg",  // Edge Add-ons
        // Avira Password Manager
        "caljgklbbfbcjjanaijlacgncafpegll",  // Chrome Web Store
        "emgfgdclgfeldebanedpihppahgngnle",  // Edge Add-ons
        // Kaspersky Password Manager
        "dhnkblpjbkfklfloegejegedcafpliaa",  // Chrome Web Store; not found on Edge Add-ons
        // True Key by McAfee
        "cpaibbcbodhimfnjnakiidgbpiehfgci",  // Chrome Web Store
        "gnnbmcifkkjgjdbkilfglpdpmidkgefn",  // Edge Add-ons
        // Bitdefender SecurePass
        "gcmahhkjkpigcpfpmdjnbiakmbdegfeh",  // Chrome Web Store
        "lnfflhmanffipgdmceonijidkpiacanc",  // Edge Add-ons
        // Trend Micro ID Protection
        "imhhfjfjfhjjjgaedcanngoffjmcblgi",  // Chrome Web Store
        "nlabjglinacgflfeigcehndaaccebpmn",  // Edge Add-ons
        // Idira, formerly CyberArk, Identity Browser Extension
        "jifcoadedkediabkmjbflemiblmnbjfk",  // Chrome Web Store
        "mblkikdcdlfpljlmgijhccbhiijkhded",  // Edge Add-ons
        // Delinea Web Password Filler
        "mfpddejbpnbjkjoaicfedaljnfeollkh",  // Chrome Web Store
        "kjldmpkefedgljefehmmfifbhnjngmbh",  // Edge Add-ons
        // Delinea Credential Manager
        "ebennojnciifnigfpjnagolafflmgilp",  // Chrome Web Store
        "mbgapjfdohjpllbeppiajkjilllilblf",  // Edge Add-ons
        // Topicus KeyHub
        "npacijjmogbimdkdpccgbnejfaheocpn",  // Chrome Web Store
        "nliljjadhmbefcmkifgbiopfcleekidd",  // Edge Add-ons
        // ESET Password Manager
        "khhapgacijodhjokkcjmleaempmchlem",  // Chrome Web Store
        "keokhigifjinncljedmendkbikiakicj",  // Edge Add-ons
        // Kee
        "mmhlniccooihdimnnjhamobppdhaolme",  // Chrome Web Store
        "amfjccmjojpjginicahekljnhhjemjec",  // Edge Add-ons
        // Psono
        "eljmjmgjkbmpmfljlmklcfineebidmlo",  // Chrome Web Store
        "abobmepfpbkapdlmfhnnkebcnhgeccbm",  // Edge Add-ons
        // heylogin
        "kghbmcgihmefcbjlfiafjcigdcbmecbf",  // Chrome Web Store
        "cajjbdjepfpnnbnhnilgeikaaicpnbhn",  // Edge Add-ons
        // Passwordstate
        "appojfilknpkghkebigcdkmopdfcjhim",  // Chrome Web Store
        "pbbamlchainnpdodbeobfpgcpffpclka",  // Edge Add-ons
        // Steganos Password Manager
        "flbkoklcepefekfcdjlabencimigaahd",  // Chrome Web Store
        "gpfoagmiheifcpjodakdcjjfjlbbchhb",  // Edge Add-ons
        // Synology C2 Password
        "kfmlopbepahlcjbkfnnklglgibbopkbk",  // Chrome Web Store
        "pcnbeeomofhokedmchichneljoamnnfl",  // Edge Add-ons
        // Passwords for Nextcloud
        "mhajlicjhgoofheldnmollgbgjheenbi",  // Chrome Web Store
        "cjmlcljdpphgdfpkngjcmeepdpcgpffk",  // Edge Add-ons
        // Okta Browser Plugin
        "glnpjglilkicbckjpbgcfkogebgllemb",  // Chrome Web Store
        "ncoafaeidnkeafiehpkfoeklhajkpgij",  // Edge Add-ons
        // Buttercup
        "heflipieckodmcppbnembejjmabajjjj",  // Chrome Web Store
        "jjcapdgcepplkhhfaopdoknkccjnlmlf",  // Edge Add-ons
        // 2FAS Pass
        "ehboaofjncodknjkngdggmpdinhdoijp",  // Chrome Web Store
        "hnhnaihhclglkfgcgggcmamjhmdjhbma",  // Edge Add-ons
        // 2FAS Auth, which copies two-factor codes
        "dbfoemgnkgieejfkaddieamagdfepnff",  // Chrome Web Store
        "dpaelbjipneennmjbjmgkdlbajncmbmj",  // Edge Add-ons
        // F-Secure Password Manager
        "hoinmffpdlgmkhckafddjleaelkdnhhk",  // Chrome Web Store
        "ljpdiapgjljgaiiilgojopoonfnnpfgj",  // Edge Add-ons
        // Password Depot
        "ggojliohohbachojmcgelnjmnjmjgidn",  // Chrome Web Store
        "eblgjcpokkiogbojdphfdgiekgjdaojn",  // Edge Add-ons
        // Samsung Pass
        "ikbdppgmbnfncggibmidpeoklmbbmpbb",  // Chrome Web Store
        "bhafgjkglbbnaobkkaihfgimpniejpkg",  // Edge Add-ons
        // Found in one store and looked for in the other without a result
        "cnlhokffphohmfcddnibpohmkdfafdli",  // Chrome Web Store: MultiPassword
        "hfdkpbblioghdghhkdppipefbchgpohn",  // Chrome Web Store: ManageEngine Password Manager Pro
        "mnilpkfepdibngheginihjpknnopchbn",  // Chrome Web Store: Strongbox AutoFill
        "fmhmiaejopepamlcjkncpgpdjichnecm",  // Chrome Web Store: KeePass Tusk
        "cnepdmlonnfpdpkkglplkpcgdpjkobkc",  // Edge Add-ons: N-able Passportal
    ]
}
