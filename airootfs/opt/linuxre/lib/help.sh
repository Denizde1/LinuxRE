#!/usr/bin/env bash

set -uo pipefail

LINUXRE_MORE_HELP_URL='https://youtu.be/dQw4w9WgXcQ?si=ycdGx4yHFjlr4KBp&utm_source=chatgpt.com'

linuxre_help_print() {
    echo "LinuxRE nedir: Arch Linux için recovery ortamıdır. Hedef sistemin kök diskini, boot yüklemesini, filesystem'ini ve ağ/uygulama durumunu güvenli şekilde inceler."
    echo
    echo "Recovery Center ne işe yarar: Disk, LUKS/LVM, Btrfs, systemd-boot, pacman, ağ ve journal gibi recovery verilerini tek yerde gösterir."
    echo
    echo "Automatic Repair ne yapar: Dosya sistemi, paket bütünlüğü, kernel/initramfs, systemd ve boot mantığını güvenli sınırlar içinde doğrular ve gerekliyse onarır."
    echo
    echo "Disk / partition işlemleri: Diskleri ve bölümleri kontrol eder, root/ESP seçimini ve mount durumunu yönetir; ancak yıkıcı işlemler için her zaman dikkatli doğrulama ister."
    echo
    echo "LUKS ve LVM diagnostics: Şifrelenmiş diskleri, mapper'ları, VG/LV hiyerarşisini ve aktiflik durumunu gösterir; güvenli tarama ve raporlama odaklıdır."
    echo
    echo "Btrfs snapshot browser: snapshot/subvolume listesi ve readonly/writable durumunu gösterir; restore yerine tarama ve izleme için kullanılır."
    echo
    echo "systemd-boot diagnostics: loader.conf, entries, EFI yolu ve default/timeout bilgilerini görüntüler; yıkıcı değişiklik yapmaz."
    echo
    echo "Pacman integrity/cache diagnostics: bozulmuş paketler, eksik dosyalar ve cache durumunu ayrıştırır; internet olmadan yeniden kurulum için paket önbelleğini değerlendirir."
    echo
    echo "Network diagnostics: interface, IP, route, DNS ve internet erişimini değerlendirir; ağ sorunlarını hızlı bir bakışta gösterir."
    echo
    echo "Recovery report: LinuxRE sürümünü, disk durumunu, boot bilgilerini, pacman ve network sonuçlarını tek bir rapora toplar; hassas bilgileri gereksiz yere yazmaz."
    echo
    echo "Yaygın durumlar:"
    echo "- Root filesystem bulunamıyor: hedef disk seçimi veya mount işlemi doğru yapılmamış olabilir."
    echo "- LUKS kilitli: encrypted disk open edilmemiş olabilir; uygun mapper ve target yönetimi gerekir."
    echo "- Btrfs snapshot yok: normaldir; snapshot tarama yalnızca bilgi amaçlıdır."
    echo "- Pacman integrity sorunları: paket dosyaları bozulmuş veya eksik olabilir; tam sistem upgrade yerine sadece gerekli paketler hedeflenir."
    echo "- Boot problemi: ESP, loader.conf, kernel/initramfs veya systemd-boot uyumsuzluğu kaynaklı olabilir."
    echo "- Ağ sorunu: DNS, route veya gateway erişimi yoksa network diagnostics bunu açıkça gösterir."
}

linuxre_open_more_help() {
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "${LINUXRE_MORE_HELP_URL}" >/dev/null 2>&1 || true
        return 0
    fi

    if command -v gio >/dev/null 2>&1; then
        gio open "${LINUXRE_MORE_HELP_URL}" >/dev/null 2>&1 || true
        return 0
    fi

    if command -v sensible-browser >/dev/null 2>&1; then
        sensible-browser "${LINUXRE_MORE_HELP_URL}" >/dev/null 2>&1 || true
        return 0
    fi

    echo "Open this link in your browser: ${LINUXRE_MORE_HELP_URL}"
    return 0
}
