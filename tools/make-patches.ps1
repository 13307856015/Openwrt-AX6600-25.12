# Builds the backport patch series for JDCloud RE-CS-02 (Athena AX6600)
# against immortalwrt v25.12.2 file contents (fetched into $TmpDir).
# Run from anywhere; outputs to <kit>\patches.
$ErrorActionPreference = 'Stop'
$TmpDir  = Join-Path $env:TEMP 'ax6600-bp'
$KitRoot = Split-Path -Parent $PSScriptRoot
$PatchDir = Join-Path $KitRoot 'patches'
New-Item -ItemType Directory -Force -Path $PatchDir | Out-Null

$repo = Join-Path $TmpDir 'repo'
if (Test-Path $repo) { Remove-Item -Recurse -Force $repo }
New-Item -ItemType Directory -Force -Path $repo | Out-Null

$files = @{
    'package/firmware/ipq-wifi/Makefile'                                        = 'tag.ipq-wifi.mk'
    'target/linux/qualcommax/image/ipq60xx.mk'                                  = 'tag.image.mk'
    'target/linux/qualcommax/ipq60xx/base-files/etc/board.d/02_network'         = 'tag.02_network'
    'target/linux/qualcommax/ipq60xx/base-files/etc/hotplug.d/firmware/11-ath11k-caldata' = 'tag.caldata'
    'target/linux/qualcommax/ipq60xx/base-files/lib/upgrade/platform.sh'        = 'tag.platform.sh'
}
foreach ($rel in $files.Keys) {
    $dst = Join-Path $repo $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
    Copy-Item (Join-Path $TmpDir $files[$rel]) $dst
}

Push-Location $repo
git init -q
git config core.autocrlf false
git config user.email 'backport@local'
git config user.name 'backport'
git add -A
git commit -q -m baseline
Pop-Location

# ---- extract the two new DTS files from the upstream commit patch ----
$patchText = Get-Content (Join-Path $TmpDir 'commit.patch')
function Get-NewFile([string]$marker) {
    $start = -1
    for ($i = 0; $i -lt $patchText.Count; $i++) {
        if ($patchText[$i] -eq "+++ $marker") { $start = $i + 1; break }
    }
    if ($start -lt 0) { throw "marker not found: $marker" }
    $body = @()
    for ($i = $start; $i -lt $patchText.Count; $i++) {
        $l = $patchText[$i]
        if ($l -like 'diff --git*') { break }
        if ($l.StartsWith('+')) { $body += $l.Substring(1) }
        elseif ($l.StartsWith('\')) { continue }
    }
    return $body
}
$dts  = Get-NewFile 'b/target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6010-re-cs-02.dts'
$dtsi = Get-NewFile 'b/target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6010-re-cs.dtsi'
$dtsPath  = Join-Path $repo 'target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6010-re-cs-02.dts'
$dtsiPath = Join-Path $repo 'target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6010-re-cs.dtsi'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dtsPath) | Out-Null
[System.IO.File]::WriteAllText($dtsPath,  (($dts  -join "`n") + "`n"))
[System.IO.File]::WriteAllText($dtsiPath, (($dtsi -join "`n") + "`n"))

# ---- edit the five existing files ----
function Edit-File([string]$rel, [scriptblock]$fn) {
    $p = Join-Path $repo $rel
    $t = [System.IO.File]::ReadAllText($p)
    $t2 = & $fn $t
    if ($t2 -eq $t) { throw "no change applied to $rel" }
    [System.IO.File]::WriteAllText($p, $t2)
}

# 1) ipq-wifi: register the board package
Edit-File 'package/firmware/ipq-wifi/Makefile' {
    param($t)
    $t = $t.Replace("`tiodata_wn-dax3000gr \`n`tlinksys_homewrk \", "`tiodata_wn-dax3000gr \`n`tjdcloud_re-cs-02 \`n`tlinksys_homewrk \")
    $t = $t.Replace(
        "`$(eval `$(call generate-ipq-wifi-package,iodata_wn-dax3000gr,I-O DATA WN-DAX3000GR))`n",
        "`$(eval `$(call generate-ipq-wifi-package,iodata_wn-dax3000gr,I-O DATA WN-DAX3000GR))`n`$(eval `$(call generate-ipq-wifi-package,jdcloud_re-cs-02,JDCloud RE-CS-02))`n")
    return $t
}

# 2) image: add the device definition
Edit-File 'target/linux/qualcommax/image/ipq60xx.mk' {
    param($t)
    $old = "endef`nTARGET_DEVICES += glinet_gl-axt1800`n`ndefine Device/linksys_mr"
    $new = @"
endef
TARGET_DEVICES += glinet_gl-axt1800

define Device/jdcloud_re-cs-02
`t`$(call Device/FitImage)
`tDEVICE_VENDOR := JDCloud
`tDEVICE_MODEL := RE-CS-02
`tSOC := ipq6010
`tBLOCKSIZE := 64k
`tKERNEL_SIZE := 6144k
`tDEVICE_DTS_CONFIG := config@cp03-c3
`tDEVICE_PACKAGES := ath11k-firmware-qcn9074 ipq-wifi-jdcloud_re-cs-02 kmod-ath11k-pci
endef
TARGET_DEVICES += jdcloud_re-cs-02

define Device/linksys_mr
"@
    return $t.Replace($old, $new)
}

# 3) board.d: network interface mapping
Edit-File 'target/linux/qualcommax/ipq60xx/base-files/etc/board.d/02_network' {
    param($t)
    return $t.Replace("`tglinet,gl-ax1800|\`n`tlinksys,mr7350|\", "`tglinet,gl-ax1800|\`n`tjdcloud,re-cs-02|\`n`tlinksys,mr7350|\")
}

# 4) caldata: eMMC ART partitions for both AHB and PCI radios
Edit-File 'target/linux/qualcommax/ipq60xx/base-files/etc/hotplug.d/firmware/11-ath11k-caldata' {
    param($t)
    $old1 = "`t`tath11k_patch_mac `$(macaddr_add `$label_mac 2) 1`n`t`tath11k_set_macflag`n`t`t;;`n`tlinksys,mr7350|\"
    $new1 = "`t`tath11k_patch_mac `$(macaddr_add `$label_mac 2) 1`n`t`tath11k_set_macflag`n`t`t;;`n`tjdcloud,re-cs-02)`n`t`tcaldata_extract_mmc `"0:ART`" 0x1000 0x10000`n`t`t;;`n`tlinksys,mr7350|\"
    $t = $t.Replace($old1, $new1)
    $old2 = "`tcambiumnetworks,xe3-4)`n`t`tcaldata_extract `"0:ART`" 0x26800 0x20000`n`t`t;;`n`tlinksys,mr7500)"
    $new2 = "`tcambiumnetworks,xe3-4)`n`t`tcaldata_extract `"0:ART`" 0x26800 0x20000`n`t`t;;`n`tjdcloud,re-cs-02)`n`t`tcaldata_extract_mmc `"0:ART`" 0x26800 0x20000`n`t`t;;`n`tlinksys,mr7500)"
    return $t.Replace($old2, $new2)
}

# 5) upgrade: eMMC support + dual-boot-slot selection
Edit-File 'target/linux/qualcommax/ipq60xx/base-files/lib/upgrade/platform.sh' {
    param($t)
    $t = $t.Replace(
        "PART_NAME=firmware`nREQUIRE_IMAGE_METADATA=1",
@"
# 25.12 does not ship find_mmc_part(); add a small self-contained helper that
# resolves GPT partition labels ("rootfs", "0:HLOS", ...) on the boot mmc.
find_mmc_part() {
`tlocal partname=`"`$1`"
`tlocal devname=`"`$2`"
`tlocal part label

`t[ -n "`$partname" ] || return 1

`tif [ -z "`$devname" ]; then
`t`tdevname=`"`$(sed -n 's/^.*root=\(\/dev\/mmcblk[0-9]*\).*`$/\1/p' /proc/cmdline)`"
`tfi
`t[ -n "`$devname" ] || devname="/dev/mmcblk0"

`tfor part in "`$devname"p*; do
`t`t[ -b "`$part" ] || continue
`t`tlabel=`"`$(sed -n 's/^PARTNAME=//p' "/sys/class/block/`${part##*/}/uevent" 2>/dev/null)`"
`t`t[ -n "`$label" ] || continue
`t`tif [ "`$label" = "`$partname" ] || [ "`$label" = "`${partname#*:}" ]; then
`t`t`techo "`$part"
`t`t`treturn 0
`t`tfi
`tdone

`treturn 1
}

PART_NAME=firmware
REQUIRE_IMAGE_METADATA=1
"@)
    $old = "`tlinksys,mr7350|\`n`tlinksys,mr7500)`n`t`tboot_part="
    $new = @"
`tjdcloud,re-cs-02)
`t`tlocal cfgpart=`$(find_mmc_part "0:BOOTCONFIG")
`t`tpart_num="`$(hexdump -e '1/1 "%01x|"' -n 1 -s 148 -C `$cfgpart | cut -f 1 -d "|" | head -n1)"
`t`tif [ "`$part_num" -eq "1" ]; then
`t`t`tCI_KERNPART="0:HLOS_1"
`t`t`tCI_ROOTPART="rootfs_1"
`t`telse
`t`t`tCI_KERNPART="0:HLOS"
`t`t`tCI_ROOTPART="rootfs"
`t`tfi
`t`temmc_do_upgrade "`$1"
`t`t;;
`tlinksys,mr7350|\
`tlinksys,mr7500)
`t`tboot_part=
"@
    return $t.Replace($old, $new)
}

# ---- emit one patch per file ----
Push-Location $repo
git add -N -- 'target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6010-re-cs-02.dts' 'target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6010-re-cs.dtsi'
$map = [ordered]@{
    '0001-ipq-wifi-register-jdcloud_re-cs-02-board.patch'   = @('package/firmware/ipq-wifi/Makefile')
    '0002-qualcommax-add-jdcloud-re-cs-02-dts.patch'        = @('target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6010-re-cs-02.dts','target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6010-re-cs.dtsi')
    '0003-qualcommax-image-add-jdcloud_re-cs-02-device.patch' = @('target/linux/qualcommax/image/ipq60xx.mk')
    '0004-qualcommax-02_network-add-jdcloud_re-cs-02.patch' = @('target/linux/qualcommax/ipq60xx/base-files/etc/board.d/02_network')
    '0005-qualcommax-caldata-add-jdcloud_re-cs-02.patch'    = @('target/linux/qualcommax/ipq60xx/base-files/etc/hotplug.d/firmware/11-ath11k-caldata')
    '0006-qualcommax-upgrade-emmc-for-jdcloud_re-cs-02.patch' = @('target/linux/qualcommax/ipq60xx/base-files/lib/upgrade/platform.sh')
}
foreach ($name in $map.Keys) {
    $out = Join-Path $PatchDir $name
    $diff = git diff --no-color -- @($map[$name])
    if (-not $diff) { throw "empty diff for $name" }
    [System.IO.File]::WriteAllText($out, (($diff -join "`n") + "`n"))
    Write-Host "wrote $name ($($diff.Count) lines)"
}
Pop-Location
