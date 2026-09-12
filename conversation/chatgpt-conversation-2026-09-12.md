# HP ProBook 11 G2 troubleshooting conversation
**Export date:** 12 September 2026  
**Topic:** Newly purchased used HP ProBook 11 G2 â€” hard freezes, Windows logs, firmware, sleep/power behaviour, BitLocker, SSD/RAM testing, HWiNFO.

> **Export note:** This Markdown file contains the conversation text that is available in the current ChatGPT session, plus a clearly marked reconstruction of the earliest laptop-troubleshooting exchanges that were compacted by the conversation system. I have not invented verbatim wording for those compacted turns.  
> **Security note:** The BitLocker 48-digit recovery password that was pasted into the chat is redacted in this export so the downloaded file does not create another copy of that secret.

---

## Earlier exchanges â€” reconstructed from available conversation context

### User
Reported that a newly purchased used **HP ProBook 11 G2** hard-froze shortly after arrival, including an early freeze after pressing **Ctrl+Alt+Delete**.

Listing/specification details supplied in the conversation included:

- HP ProBook 11 G2
- 11.6-inch display
- Intel Core i3-6100U 2.3 GHz
- 4 GB DDR4 RAM
- Intel HD Graphics
- 128 GB SSD
- webcam, Wi-Fi N, HDMI, card reader, 3Ã— USB 3.0
- AC adaptor/cable
- battery tested working
- Windows 11 Pro installed by the seller
- 3-month warranty

The laptop was received on **Friday 11 September 2026**.

### Assistant
Recommended preserving evidence and avoiding opening, upgrading, wiping, or flashing the machine before the warranty situation was understood.

Guided the user into **HP UEFI Diagnostics** (`Esc` â†’ `F2`).

### User
Ran the HP diagnostics.

### Assistant
Interpreted the results:

- **Memory Quick Check: PASSED**
- **Hard Drive Quick Check:**
  - SMART Check: **PASSED**
  - Short DST: **PASSED**

Explained that these tests reduce the likelihood of an obvious RAM/SSD failure but do not eliminate intermittent faults.

### User
Shared Task Manager information.

### Assistant
Noted the system appeared normal at idle:

- CPU ~3%
- CPU speed ~2.30 GHz
- Memory ~2.4/3.8 GB (~62%)
- SSD 0%
- GPU 0%

Explained that **4 GB RAM is cramped for Windows 11**, but 4 GB alone should not normally produce a complete hard lock.

### User
On **12 September 2026 at about 2:14 pm**, reported another hard freeze while the machine was effectively idle / at the lock screen.

### Assistant
Treated the second hard freeze in roughly a day as significant and recommended looking at Windows logs before changing the system.

Suggested checking:

- Reliability Monitor (`perfmon /rel`)
- Event Viewer â†’ Windows Logs â†’ System
- WHEA-Logger
- Disk / storahci / iaStorA
- Display
- BugCheck
- Kernel-Power 41
- EventLog 6008

Explained that **Kernel-Power 41** and **EventLog 6008** usually record the aftermath of an unclean shutdown rather than the root cause.

### User
Shared Event Viewer screenshots.

### Assistant
Interpreted several events:

- **TPM-WMI Event 1801:** Windows had updated Secure Boot certificates available that had not yet been applied to firmware; this was *not* evidence of TPM hardware failure.
- **Kernel-PnP Event 219:** `WUDFRd` failed to load for the HP wireless button driver; interesting as an old/unsupported HP driver, but not a strong whole-system-freeze explanation.
- **BitLocker-Driver Event 24641:** unexpected error retrieving the BitLocker volume master key during restart; likely secondary to the forced shutdown/restart.
- **DistributedCOM 10016:** common Windows warning, unlikely to explain a hard lock.
- **winsrv 100:** Explorer delayed shutdown by about five seconds; not evidence of the freeze itself.

The absence of a BSOD or a clear WHEA/storage/display event kept low-level firmware/driver or intermittent hardware faults in consideration.

---

## Available transcript

### Assistant
Yep â€” Iâ€™ve now parsed the actual **`a.evtx`**, and it gives us something useful.

The **12 Sep freeze is a genuine hard hang**, not a blue screen:

- **Kernel-Power Event 41:** 2:15:59 pm
- `BugcheckCode = 0`
- all bugcheck parameters = `0`
- `SleepInProgress = 0`
- `ConnectedStandbyInProgress = 0`
- `WHEABootErrorCount = 0`
- `LidState = 1` â€” lid open
- `PowerButtonTimestamp` decodes to about **2:15:25 pm**, which fits you forcing it off.

So Windows simply **stopped responding**. Thereâ€™s no recorded BSOD or WHEA hardware fault immediately beforehand. I also found no current `storahci`, `iaStor`, WHEA-Logger or Intel display crash around the freeze.

Thereâ€™s also evidence of the **first incident**: the log records an unexpected shutdown on **11 Sep at about 5:29 pm**, which lines up with when it first froze after arriving.

But I found something much more interesting: the current events repeatedly report:

**HP BIOS: `N92 Ver. 01.04`**

That is *ancient*. HP released **N92 BIOS 01.60** for this exact **HP ProBook 11 G2 Education Edition** in April 2023.

So my suspicion order has changed:

**Old BIOS/firmware + Windows 11 driver/power-management stack â†’ most interesting lead**  
then Windows installation itself â†’ then intermittent hardware.

Before reinstalling anything, press **Win + R â†’ `msinfo32`** and send me the screen showing **BIOS Version/Date**.

If it confirms **01.04**, I think updating the BIOS is our next move.

---

### Assistant
Yep â€” this confirms the BIOS issue pretty clearly.

Your system report says this is an **HP ProBook 11 G2**, with **HP N92 BIOS 01.04 dated 2 Nov 2016**. HPâ€™s official BIOS package for this exact model is **N92 01.60**, released in 2023 and marked **Critical**; HP also says it has **no prerequisite BIOS version**, so you can update directly from 01.04.

One correction to what I said earlier: **01.04 â†’ 01.60 does not mean literally â€œ56 BIOS revisions behindâ€**. There may not have been every intervening numbered release. But it is still an enormous firmware age gap â€” roughly 6Â½ years.

Thereâ€™s another useful clue in your report: with only **4 GB RAM**, Windows had just **330 MB physical memory available** when you generated the report. That absolutely explains sluggishness, although I still wouldnâ€™t expect it alone to cause the kind of total hard freeze youâ€™ve seen.

So Iâ€™d now do this in order:

1. **Check BitLocker first** because we saw BitLocker errors. Open Terminal/Admin CMD and run:
   ```cmd
   manage-bde -status C:
   ```
2. If encryption is enabled, make sure we have the **recovery key** before touching firmware.
3. Update the BIOS to **N92 01.60**.
4. Use it normally and see whether another hard freeze occurs.
5. Then upgrade to **8 GB RAM** regardless, because 4 GB is genuinely inadequate for this Windows 11 install.

Send me the output of `manage-bde -status C:` and Iâ€™ll tell you whether itâ€™s safe to proceed with the BIOS flash.

---

### User â€” 2026-09-12 04:30:55Z
```text
Windows PowerShell
Copyright (C) Microsoft Corporation. All rights reserved.

PS C:\Users\User> manage-bde -status C:
BitLocker Drive Encryption: Configuration Tool version 10.0.26100
Copyright (C) 2013 Microsoft Corporation. All rights reserved.

Volume C: []
[OS Volume]

    Size:                 118.16 GB
    BitLocker Version:    2.0
    Conversion Status:    Encryption in Progress
    Percentage Encrypted: 99.0%
    Encryption Method:    XTS-AES 128
    Protection Status:    Protection Off
    Lock Status:          Unlocked
    Identification Field: Unknown
    Key Protectors:
        Numerical Password
        TPM

PS C:\Users\User>
``²È="25…ˆÔØ´ÈàÐÍ™‰ÈÜÌØÑõpÀ)•Ù¥”•ÍÉ¥ÁÑ¥½¸è€€€€€€€€!@8äÈMåÍÑ•´¥ÉµÝ…É”€ÀÄ¸ØÀ)±…ÍÌ9…µ”è€€€€€€€€€€€€€€€€¥ÉµÝ…É”)±…ÍÌU%è€€€€€€€€€€€€€€€€í˜É”Ý‘ÜÈ´ØÐØà´Ñ”ÌØµˆÙ˜Ä´ØÐàá˜ÐÉŒÅˆÔÉô)5…¹Õ™…ÑÕÉ•È9…µ”è€€€€€€€€€!@%¹Œ¸)MÑ…ÑÕÌè€€€€€€€€€€€€€€€€€€€€AÉ½‰±•´)AÉ½‰±•´½‘”è€€€€€€€€€€€€€€€ÄÀ€ ÁàÁ¤m5}AI=	}%1}MQIQt)AÉ½‰±•´MÑ…ÑÕÌè€€€€€€€€€€€€€ÁáÀÀÀÀÀÀÄ)É¥Ù•È9…µ”è€€€€€€€€€€€€€€€½•´Èà¹¥¹˜()ALéqUÍ•ÉÍqUÍ•Èø•ÐµA¡åÍ¥…±¥Í¬ð•ÐµMÑ½É…•I•±¥…‰¥±¥Ñå½Õ¹Ñ•Èð™°()=‰©•Ñ%€€€€€€€€€€€€€€€€èìÅõqqM-Q=@µÅTäàÁqÉ½½Ð½5¥É½Í½™Ð½]¥¹‘½ÝÌ½MÑ½É…”½AÉ½Ù¥‘•ÉÍ}ØÉqMAM}MÑ½É…•I•±¥…‰¥±¥Ñå½Õ¹Ñ•È¹=‰©•Ñ%ô‰ìÕŒÀåˆàÄ´ÄÑÀ´ÄÅ˜Ä´áŒå„´àÀÙ”Ù˜Ù”ØäØÍôéIéìÙ„ÐÝ•Ý˜µ™˜ÀÄµ”ÌÐÈ´ÄÍ„Ä´á™……ˆÔÌäàÑ‰‰ôˆ)•Ù¥•%€€€€€€€€€€€€€€€€è€À)±ÕÍ¡1…Ñ•¹å5…à€€€€€€€€€è€ÄÄÔ)A½Ý•É=¹!½ÕÉÌ€€€€€€€€€€€€è€ÈÈÐÈ)I•…‘ÉÉ½ÉÍ½ÉÉ•Ñ•€€€€€è€À)I•…‘ÉÉ½ÉÍQ½Ñ…°€€€€€€€€€è€À)I•…‘ÉÉ½ÉÍU¹½ÉÉ•Ñ•€€€è€À)I•…‘1…Ñ•¹å5…à€€€€€€€€€€è€Ðàà)Q•µÁ•É…ÑÕÉ”€€€€€€€€€€€€€è€ÐÀ)]•…È€€€€€€€€€€€€€€€€€€€€è€À)]É¥Ñ•1…Ñ•¹å5…à€€€€€€€€€è€ÄÄÔ()ALéqUÍ•ÉÍqUÍ•Èø•Ðµ¥µ%¹ÍÑ…¹”]¥¸ÌÉ}	…Í•	½…É()5…¹Õ™…ÑÕÉ•È€è!@)M•É¥…±9Õµ‰•È€èAUÍ]HÜÔÈ)AÉ½‘ÕÐ€€€€€€è€àÄá()ALéqUÍ•ÉÍqUÍ•Èø•Ðµ¥µ%¹ÍÑ…¹”]¥¸ÌÉ}	%=L()M5	%=M	%=MY•ÉÍ¥½¸€è8äÈY•È¸€ÀÄ¸ÀÐ)5…¹Õ™…ÑÕÉ•È€€€€€€è!@)9…µ”€€€€€€€€€€€€€€è8äÈY•È¸€ÀÄ¸ÀÐ)M•É¥…±9Õµ‰•È€€€€€€è€áÜÄÜÑYA)Y•ÉÍ¥½¸€€€€€€€€€€€è!AE=4€´€À()ALéqUÍ•ÉÍqUÍ•ÈøÁ½Ý•É™œ€½ÍåÍÑ•µÍ±••Á‘¥…¹½ÍÑ¥Ì€½½ÕÑÁÕÐ€ˆ‘•¹ØéUMIAI=%1q•Í­Ñ½ÁqÍ±••ÀµÉ•Á½ÉÐ¹¡Ñµ°ˆ)Q¡”ÍåÍÑ•´Í±••À‘¥…¹½ÍÑ¥ÌÉ•Á½ÉÐ¡…Ì‰••¸‘•ÁÉ•…Ñ•…¹É•Á±…•Ý¥Ñ Ñ¡”ÍåÍÑ•´Á½Ý•ÈÉ•Á½ÉÐ¸)A±•…Í”ÕÍ”Ñ¡”½µµ…¹€‰Á½Ý•É™œ€½ÍåÍÑ•µÁ½Ý•ÉÉ•Á½ÉÐˆ¥¹ÍÑ•…¸()ALéqUÍ•ÉÍqUÍ•ÈøÁ½Ý•É™œ€½ÍåÍÑ•µÁ½Ý•ÉÉ•Á½ÉÐ)M±••ÀMÑÕ‘äÉ•Á½ÉÐÍ…Ù•Ñ¼™¥±”Á…Ñ éqUÍ•ÉÍqUÍ•ÉqÍ±••ÁÍÑÕ‘äµÉ•Á½ÉÐ¹¡Ñµ°¸)€()UÍ•ÈÕÁ±½…‘•Í±••ÁÍÑÕ‘äµÉ•Á½ÉÐ¹¡Ñµ±€¸((ŒŒŒÍÍ¥ÍÑ…¹Ð)¹…±åÍ•Ñ¡”Á½Ý•ÈÉ•Á½ÉÐ…¹½ÉÉ•Ñ•Ñ¡”•…É±¥•È¥¹Ñ•ÉÁÉ•Ñ…Ñ¥½¸è((¨©Q¡”ÑÝ¼™É••é•ÌÝ•É”¹½ÐÍ¥µÁ±ä½É‘¥¹…ÉäLÌÉ•ÍÕµ”™…¥±ÕÉ•Ì¸¨¨Q¡”ÍÑÉ½¹•È½µµ½¸Á…ÑÑ•É¸Ý…Ìè((¨©!å‰É¥Í¡ÕÑ‘½Ý¸€¼…ÍÐMÑ…ÉÑÕÀƒŠHLÐÉ•ÍÕµ”ƒŠH¥¹ÍÑ…‰¥±¥ÑäÝ¥Ñ¡¥¸„™•Üµ¥¹ÕÑ•Ì¸¨¨()Q¡”É•Á½ÉÐÍ¡½Ý•è((´Ñ¡”™¥ÉÍÐ¥¹¥‘•¹Ð™½±±½Ý•„€¨©!å‰É¥M¡ÕÑ‘½Ý¸¨¨…¹€¨©I•ÍÕµ”LÐ¥ÍÁ±…ä	ÕÉÍÐ¨¨°Ñ¡•¸±…Ñ•È…ÑÑ•µÁÑ•LÌÍÑ…¹‘‰ä…¹‘¥¹½Ð½µÁ±•Ñ”¹½Éµ…±±äì(´Ñ¡”Í•½¹¥¹¥‘•¹Ð……¥¸™½±±½Ý•…¸LÐ½…ÍÐMÑ…ÉÑÕÀÉ•ÍÕµ”‰•™½É”Ñ¡”…‰¹½Éµ…°Í¡ÕÑ‘½Ý¸ì(´Á½Ý•É™œ€½ ½™™€Ñ¡•É•™½É”É•µ½Ù•…¸¥µÁ½ÉÑ…¹ÐÙ…É¥…‰±”‰•…ÕÍ”¥Ð‘¥Í…‰±•Ì‰½Ñ ¡¥‰•É¹…Ñ¥½¸…¹…ÍÐMÑ…ÉÑÕÀ¸()I•½µµ•¹‘•„±•…¸½Ñ•ÍÐ‰•™½É”™±…Í¡¥¹œÑ¡”	%=Lè()Á½Ý•ÉÍ¡•±°)Á½Ý•É™œ€½¡…¹”ÍÑ…¹‘‰äµÑ¥µ•½ÕÐµ…Œ€À)Á½Ý•É™œ€½¡…¹”ÍÑ…¹‘‰äµÑ¥µ•½ÕÐµ‘Œ€À)Í¡ÕÑ‘½Ý¸€½Ì€½Ð€À)€()Q¡•¸Á•É™½É´Í•Ù•É…°•¹Õ¥¹”™Õ±°Í¡ÕÑ‘½Ý¸ƒŠH½±‰½½Ðå±•ÌÝ¥Ñ ¹¼Í±••À¸()±Í¼¹½Ñ•Ñ¡…ÐMM•Ù¥‘•¹”É•µ…¥¹•É•…ÍÍÕÉ¥¹œè((´€À½ÉÉ•Ñ•É•…•ÉÉ½ÉÌ(´€ÀÑ½Ñ…°É•…•ÉÉ½ÉÌ(´€ÀÕ¹½ÉÉ•Ñ•É•…•ÉÉ½ÉÌ(´MMÑ•µÁ•É…ÑÕÉ”…‰½ÕÐ€ÐÃ
Á()ÕÉÉ•¹ÐÍÕÍÁ•ÐÉ…¹­¥¹œÝ…Ìè((Ä¸…ÍÐMÑ…ÉÑÕÀ½LÐ€¬½±½µ•ÍÍä!@Á½Ý•È½‘É¥Ù•ÈÍÑ…¬(È¸¹¥•¹Ð	%=L€ÀÄ¸ÀÐ€¼™¥ÉµÝ…É”µ¥Íµ…Ñ (Ì¸±½¹•MåÍÁÉ•À]¥¹‘½ÝÌ¥µ…”(Ð¸A…ÉÑ¥Õ±…È½¹•á…¹Ð½!@¡½Ñ­•ä½Á½Ý•È‘É¥Ù•È(Ô¸5½Ñ¡•É‰½…É¡…É‘Ý…É”™…Õ±Ð(Ø¸MM½I4™…Õ±ÐƒŠP½¹Í¥‘•É…‰±ä±•ÍÌÍÕÁÁ½ÉÑ•‰äÑ¡”ÕÉÉ•¹Ð•Ù¥‘•¹”((´´´((ŒŒŒUÍ•ÈƒŠP€ÈÀÈØ´Àä´ÄÈ€ÀÔèÀÀèÀÍh)¥ÌÑ¡•É”…¹äÍ½™ÑÝ…É”¤…¸‘½Ý¹±½…™É•”Ñ¼‘¼µ½É”Ñ•ÍÑ¥¹œ™½Èå½Ôü((ŒŒŒÍÍ¥ÍÑ…¹Ð)e•Ì¸Q¡•É”…É”„™•Ü™É•”Ñ½½±ÌÑ¡…ÐÝ½Õ±¥Ù”ÕÌµÕ ‰•ÑÑ•È•Ù¥‘•¹”°…¹'ŠeÕÍ”Ñ¡•´¥¸Ñ¡¥Ì½É‘•ÈÉ…Ñ¡•ÈÑ¡…¸¥¹ÍÑ…±±¥¹œ„Á¥±”½˜É…¹‘½´‘¥…¹½ÍÑ¥ŒÍ½™ÑÝ…É”¸((Ä¸€¨©!]¥9<ØÐ¨¨ƒŠPÑ¡¥Ì¥ÌÑ¡”½¹”$Ý…¹Ð™¥ÉÍÐ¸%Ð…¸±½œÑ•µÁ•É…ÑÕÉ•Ì°AT±½­Ì°Ñ¡É½ÑÑ±¥¹œ°‰…ÑÑ•Éä½Á½Ý•ÈÉ•…‘¥¹Ì…¹¡…É‘Ý…É”Í•¹Í½ÉÌ½¹Ñ¥¹Õ½ÕÍ±äÝ¡¥±”å½ÔÕÍ”Ñ¡”±…ÁÑ½À¸(È¸€¨©=PA•ÉÍ½¹…°¨¨ƒŠPÕÍ•™Õ°™½ÈÍÑ…‰¥±¥ÑäÑ•ÍÑ¥¹œì¥¹¥Ñ¥…±±äAT€¬I4™½È…‰½ÕÐ€ÄÔµ¥¹ÕÑ•ÌÉ…Ñ¡•ÈÑ¡…¸„µ…á¥µÕ´Á½Ý•ÈÑ½ÉÑÕÉ”Ñ•ÍÐ¸(Ì¸€¨©5•µQ•ÍÐàØÉ•”¨¨ƒŠPÍÑÉ½¹•ÈI4Ñ•ÍÑ¥¹œÑ¡…¸Ñ¡”!@ÅÕ¥¬Ñ•ÍÐ…¹ÉÕ¹Ì½ÕÑÍ¥‘”]¥¹‘½ÝÌ¸(Ð¸€¨©ÉåÍÑ…±¥Í­%¹™¼¨¨ƒŠP•áÁ½Í•Ì…ÑÕ…°MMM5IP…ÑÑÉ¥‰ÕÑ•Ì¸(Ô¸€¨©1…Ñ•¹å5½¸!½µ”‘¥Ñ¥½¸¨¨ƒŠPÕÍ•™Õ°™½È¥¹Ù•ÍÑ¥…Ñ¥¹œÁÉ½‰±•µ…Ñ¥ŒA½%MH‰•¡…Ù¥½ÕÈ™É½´½±‘É¥Ù•ÉÌÍÕ …Ì½¹•á…¹Ð°%¹Ñ•°É…Á¡¥Ì°]¤µ¤½ÈA$½µÁ½¹•¹ÑÌ¸()I•½µµ•¹‘•ÍÑ…ÉÑ¥¹œÝ¥Ñ €¨©!]¥9<¨¨…¹€¨©ÉåÍÑ…±¥Í­%¹™¼¨¨°Ñ¡•¸=P°Ý¥Ñ 5•µQ•ÍÐàØ±…Ñ•È¸()±Í¼É•½µµ•¹‘•­••Á¥¹œ€¨©…ÍÐMÑ…ÉÑÕÀ…¹¡¥‰•É¹…Ñ¥½¸‘¥Í…‰±•¨¨‘ÕÉ¥¹œÑ¡¥ÌÑ•ÍÑ¥¹œ¸((´´´((ŒŒŒUÍ•ÈƒŠP€ÈÀÈØ´Àä´ÄÈ€ÀÔèÀÔèÔåh)UÁ±½…‘•„ÍÉ••¹Í¡½Ð½˜Ñ¡”!]¥9<ØÐMåÍÑ•´MÕµµ…Éä¸((ŒŒŒÍÍ¥ÍÑ…¹Ð)A•É™•ÐƒŠPÑ¡¥Ì½¹™¥ÉµÌÑ¡”¡…É‘Ý…É”•á…Ñ±ä°…¹€¨©¹½Ñ¡¥¹œ½¸Ñ¡¥ÌÍÕµµ…ÉäÁ…”ÍÉ•…µÌ¥µµ•‘¥…Ñ”¡…É‘Ý…É”™…¥±ÕÉ”¨¨¸()!]¥9<¥ÌÍ••¥¹œè((´€¨©!@AÉ½	½½¬€ÄÄÈ€¼‰½…É€àÄá¨¨(´€¨©¤Ì´ØÄÀÁT¨¨°€È½É•Ì€¼€ÐÑ¡É•…‘Ì(´€¨©	%=L8äÈ€ÀÄ¸ÀÐ‘…Ñ•€È9½Ø€ÈÀÄØ¨¨(´€¨¨ÐHÐ´ÈÄÌÌ¨¨°½¹”M,!å¹¥àµ½‘Õ±”°ÕÉÉ•¹Ñ±ä€¨©Í¥¹±”µ¡…¹¹•°¨¨(´€¨©%¹Ñ•°!€ÔÈÀ¨¨(´€¨©M…µÍÕ¹œ5i9QdÄÈá!!@´ÀÀÁ Ä€ÄÈàMQMM¨¨(´]¥¹‘½ÝÌ€ÄÄAÉ¼€ÈÑ È(´U$‰½½Ð°M•ÕÉ”	½½Ð…¹QA4…±°‘•Ñ•Ñ•()Q¡•¸É•ÅÕ•ÍÑ•€¨©½¹Ñ¥¹Õ½ÕÌ!]¥9<Í•¹Í½È±½¥¹œ¨¨è((´±½Í”MåÍÑ•´MÕµµ…Éäì(´½Á•¸€¨©M•¹Í½ÉÌ¨¨ì(´±¥¬€¨©MÑ…ÉÐ1½¥¹œ¨¨ì(´Í…Ù”„MXÍÕ …Ìè()Ñ•áÐ)•Í­Ñ½ÁqAÉ½	½½¬µ!]¥9<µ±½œ¹ÍØ)€()I•½µµ•¹‘•ÕÍ¥¹œÑ¡”±…ÁÑ½À¹½Éµ…±±ä™½È€¨¨ÈÃŠLÌÀµ¥¹ÕÑ•Ì¨¨Ý¡¥±”­••Á¥¹œ¥Ð…Ý…­”™½ÈÑ¡”™¥ÉÍÐÑ•ÍÐ¸()I•ÅÕ•ÍÑ•µ½¹¥Ñ½É¥¹œ½˜è((´ATA…­…”½½É”Ñ•µÁ•É…ÑÕÉ•Ì(´AT±½­Ì½•™™•Ñ¥Ù”±½­Ì(´Ñ¡•Éµ…°Ñ¡É½ÑÑ±¥¹œ™±…Ì(´µ•µ½Éä±½…(´MMÑ•µÁ•É…ÑÕÉ”(´‰…ÑÑ•ÉäÙ½±Ñ…”½¡…É”½‘¥Í¡…É”É…Ñ”(´AT±½­Ì½±½…(´Á½Ý•Èµ±¥µ¥Ð½Ñ¡É½ÑÑ±¥¹œ¥¹‘¥…Ñ½ÉÌ()%˜Ñ¡”±…ÁÑ½À™É••é•ÌÝ¡¥±”±½¥¹œ°ÁÉ•Í•ÉÙ”Ñ¡”MX…™Ñ•ÈÉ•‰½½Ð‰•…ÕÍ”Ñ¡”™¥¹…°™•ÜÍ•½¹‘Ìµ…ä‰”•ÍÁ•¥…±±äÕÍ•™Õ°¸()±Í¼¥‘•¹Ñ¥™¥•Ñ¡”¥¹ÍÑ…±±•µ•µ½Éäµ½‘Õ±”…Ìè((¨©M,!å¹¥à!5ÐÔÅLÙHá8µQ°€ÐHÐ´ÈÄÌÌ¨¨((´´´((ŒŒŒUÍ•ÈƒŠP€ÈÀÈØ´Àä´ÄÈ€ÀÔèÄÀèÄÉh)M…Ù”½ÕÈ•¹Ñ¥É”½¹Ù•ÉÍ…Ñ¥½¸Í¼™…ÈÑ¼„5™¥±”Á±•…Í”$…¸‘½Ý¹±½…((´´´((ŒŒ¥±•Ì…¹•Ù¥‘•¹”µ•¹Ñ¥½¹•½ÈÕÁ±½…‘•¥¸Ñ¡¥Ì½¹Ù•ÉÍ…Ñ¥½¸((´„¹•ÙÑá€(´ˆ¹•ÙÑá€(´Œ¹•ÙÑá€(´¹•ÙÑá€(´”¹•ÙÑá€(´˜¹•ÙÑá€(´œ¹•ÙÑá€(´ ¹•ÙÑá€(´¤¹•ÙÑá€(´Í•½¹‘ÕÁ±¥…Ñ”‰…Ñ ½˜Ñ¡”…‰½Ù”YQ`™¥±•Ì(´Í•ÑÕÁ…Á¤¹‘•Ø¹±½€(´‰…ÑÑ•ÉäµÉ•Á½ÉÐ¹¡Ñµ±€(´Í±••ÁÍÑÕ‘äµÉ•Á½ÉÐ¹¡Ñµ±€(´!]¥9<ØÐMåÍÑ•´MÕµµ…ÉäÍÉ••¹Í¡½Ð(´€ÄÄÄÄ Ä¤¹ÑáÑ€€¼ÍåÍÑ•´µ¥¹™½Éµ…Ñ¥½¸É•±…Ñ•Ñ•áÐ•áÁ½ÉÐ¡Ì¤((´´´((ŒŒÕÉÉ•¹Ð‘¥…¹½ÍÑ¥ŒÍÑ…Ñ”…ÐÑ¡”Á½¥¹Ð½˜•áÁ½ÉÐ()Q¡”ÍÑÉ½¹•ÍÐ•Ù¥‘•¹”Í¼™…È¥Ìè((´ÑÝ¼•¹Õ¥¹”¡…É¡…¹ÌÝ¥Ñ ¹¼	M=ì(´!@ÅÕ¥¬I4Ñ•ÍÐÁ…ÍÍ•ì(´!@MMM5IP€¬M¡½ÉÐMPÁ…ÍÍ•ì(´]¥¹‘½ÝÌÍÑ½É…”É•±¥…‰¥±¥Ñä½Õ¹Ñ•ÉÌÍ¡½Ü¹¼É•…•ÉÉ½ÉÌì(´ÕÉÉ•¹ÐMMÑ•µÁ•É…ÑÕÉ”…É½Õ¹€ÐÃ
Áì(´…ÑÕ…°µ½Ñ¡•É‰½…É¥Ì€¨©!@€àÄá¨¨ì(´…ÑÕ…°AT¥Ì€¨©%¹Ñ•°½É”¤Ì´ØÄÀÁT¨¨ì(´	%=L¥Ì€¨©8äÈ€ÀÄ¸ÀÐ€ È9½Ø€ÈÀÄØ¤¨¨ì(´]¥¹‘½ÝÌ¡…Ì…¸€¨©!@8äÈMåÍÑ•´¥ÉµÝ…É”€ÀÄ¸ØÀ¨¨‘•Ù¥”ÍÑ…•‰ÕÐ¥Ð¥Ì€¨©½‘”€ÄÀ€¼%1}MQIP¨¨ì(´]¥¹‘½ÝÌ¥¹ÍÑ…±±…Ñ¥½¸Ý…Ì€¨©MåÍÁÉ•ÀµÉ•ÍÁ•¥…±¥Í•¨¨½¹Ñ¼Ñ¡¥Ì±…ÁÑ½À¥µµ•‘¥…Ñ•±ä‰•™½É”Í…±”…¹É•Ñ…¥¹ÌÍÕ‰ÍÑ…¹Ñ¥…°¡¥ÍÑ½É¥…°¡…É‘Ý…É”½‘•Ù¥”ÍÑ…Ñ”™É½´½Ñ¡•Èµ…¡¥¹•Ìì(´Ñ¡”]¥¹‘½ÝÌ¥µ…”½¹Ñ…¥¹Ì½±½µ¥Íµ…Ñ¡•!@½=4‘É¥Ù•ÉÌ…¹Í•ÉÙ¥¥¹œ¥ÍÍÕ•Ìì(´‰½Ñ ™É••é”¥¹¥‘•¹ÑÌ…É”ÍÑÉ½¹±ä…ÍÍ½¥…Ñ•Ý¥Ñ €¨©LÐ€¼…ÍÐMÑ…ÉÑÕÀ€¼Á½Ý•ÈµÍÑ…Ñ”ÑÉ…¹Í¥Ñ¥½¹Ì¨¨ì(´¡¥‰•É¹…Ñ¥½¸…¹…ÍÐMÑ…ÉÑÕÀ¡…Ù”¹½Ü‰••¸‘¥Í…‰±•Ý¥Ñ Á½Ý•É™œ€½ ½™™€ì(´	¥Ñ1½­•ÈÉ•µ…¥¹Ì…Ð€¨¨ää”¹ÉåÁÑ¥½¸¥¸AÉ½É•ÍÌ¨¨°Ý¥Ñ ÁÉ½Ñ•Ñ¥½¸‘¥Í…‰±•½ÍÕÍÁ•¹‘•ì(´Ñ¡”¹•áÐ±•…¸‘¥…¹½ÍÑ¥Œ•áÁ•É¥µ•¹Ð¥Ì½±µ‰½½Ð½Á•É…Ñ¥½¸Ý¥Ñ Í±••À‘¥Í…‰±•ì(´!]¥9<±½¥¹œ¥ÌÑ¡”¹•áÐ±¥Ù”µ½¹¥Ñ½É¥¹œÍÑ•Àì(´	%=L€ÀÄ¸ØÀÉ•µ…¥¹Ì„±¥­•±ä™ÕÑÕÉ”½ÉÉ•Ñ¥Ù”ÍÑ•À½¹”	¥Ñ1½­•ÈÍÑ…Ñ”¥ÌÍ…™•±ä¡…¹‘±•ì(´„±•…¸]¥¹‘½ÝÌ¥¹ÍÑ…±°É•µ…¥¹Ì‘•Í¥É…‰±”¥˜Ñ¡”µ…¡¥¹”¥Ì­•ÁÐì(´¥˜ÕÁ‘…Ñ•™¥ÉµÝ…É”€¬±•…¸Í½™ÑÝ…É”ÍÑ¥±°ÁÉ½‘Õ”¡…É™É••é•Ì°Ñ¡”€Ìµµ½¹Ñ Í•±±•ÈÝ…ÉÉ…¹Ñä‰•½µ•ÌÑ¡”Í•¹Í¥‰±”¹•áÐÍÑ•À¸((