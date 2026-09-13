# INSTALL.md — Instalação do AlmaLinux com LUKS2 + LVM

Grupo 3 — AlmaLinux 10.2
Parte: criação da VM, particionamento criptografado (LUKS2) sobre LVM, e
extensão de disco.

---

## 1. Pré-requisitos

- VirtualBox instalado
- ISO `AlmaLinux-10.2-x86_64-minimal.iso` baixada
- Hash SHA-256 da ISO conferido contra o CHECKSUM oficial em
  https://almalinux.org/get-almalinux/

```bash
sha256sum AlmaLinux-10.2-x86_64-minimal.iso
```

---

## 2. Criar a VM no VirtualBox

1. **Novo** → Nome: `AlmaLinux` → Tipo: `Linux` → Versão: `Red Hat (64-bit)`
2. Memória: **4096 MB**
3. Disco rígido: novo disco virtual, **VDI**, alocação dinâmica, **60 GB**
4. Antes de ligar, em **Configurações**:
   - **Sistema → Placa-mãe**: marcar **"Habilitar EFI"**
   - **Sistema → Processador**: 2 CPUs
   - **Armazenamento**: montar a ISO do AlmaLinux no controlador SATA
   - **Rede → Adaptador 1**: modo **NAT** (nunca Bridge)
5. Ligar a VM

📸 **Print:** tela "Detalhes" da VM no VirtualBox Manager, mostrando RAM,
CPUs, disco e rede → `evidencias/00-specs-vm-antes-extend.png`

---

## 3. Particionamento manual (LUKS2 + LVM)

Na tela "Destino da instalação" do Anaconda:

1. Selecionar o disco de 60 GB
2. Marcar **"Vou configurar particionamento"**
3. Escolher o esquema **LVM**

**Ordem de criação das partições/LVs:**

1. `/boot/efi` — 1024 MiB — **Standard Partition**, sem criptografia
2. `/boot` — 1024 MiB — **Standard Partition**, sem criptografia
3. `/` (primeiro LV) — criar como **LVM**
4. No **Grupo de Volume**, clicar em **"Modificar..."** e:
   - Marcar **"Criptografar"** (aplica o LUKS2 ao VG inteiro, não a cada LV)
   - Política de Tamanho: **"O maior possível"**
5. Criar os LVs restantes normalmente — todos herdam a criptografia do
   mesmo Volume Group automaticamente

**Esquema final:**

| Partição/LV | Tamanho | Ponto de montagem | FS |
|---|---|---|---|
| sda1 | 1 GiB | /boot/efi | FAT32 (fora do LUKS) |
| sda2 | 1 GiB | /boot | xfs (fora do LUKS) |
| sda3 | ~58 GiB | → container LUKS2 único | — |
| lv root | 15 GiB | / | xfs |
| lv var | 8 GiB | /var | xfs |
| lv var_log | 5 GiB | /var/log | xfs |
| lv var_tmp | 3 GiB | /var/tmp | xfs |
| lv home | 10 GiB | /home | xfs |
| lv tmp | 3 GiB | /tmp | xfs |
| lv swap | 4 GiB | swap | swap |
| — | ~9 GiB livres | (reservado p/ snapshot) | — |

> ⚠️ O Anaconda pede a passphrase do LUKS **duas vezes** antes de aceitar
> as mudanças no disco. Anote-a em local compartilhado do grupo nesse
> momento — não existe recuperação sem ela.

📸 **Print:** tela de resumo do particionamento do Anaconda antes de
confirmar → `evidencias/01-resumo-particionamento-anaconda.png`

Confirmar e seguir a instalação normalmente (usuário, senha de root, etc).

---

## 4. Primeiro boot

No boot, o sistema vai pedir a passphrase do LUKS para desbloquear o disco.
Isso acontece **toda vez que a VM liga**.

Depois de logado, conferir SELinux:

```bash
getenforce      # precisa retornar "Enforcing"
sestatus
```

Se retornar `Permissive`:

```bash
touch /.autorelabel
reboot
```

---

## 5. Snapshot e evidências (pré-extend)

**Snapshot:** no VirtualBox Manager, botão direito na VM → Câmeras
(Snapshots) → Tirar → nome `pos-instalacao-limpa`.

**Evidências em texto:**

```bash
{
  echo "== lsblk -f =="; lsblk -f
  echo "== luksDump =="; cryptsetup luksDump /dev/sda3
  echo "== pvs/vgs/lvs =="; pvs; vgs; lvs
  echo "== findmnt =="; findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS
  echo "== fstab =="; cat /etc/fstab
  echo "== crypttab =="; cat /etc/crypttab
} > evidencias-disco.txt
```

```bash
{
  echo "== os-release =="; cat /etc/os-release
  echo "== uname -r =="; uname -r
  echo "== getenforce =="; getenforce
  echo "== sestatus =="; sestatus
} > evidencias-sistema-selinux.txt
```

---

## 6. Adicionar o segundo disco (20 GB) e extender o LVM

1. Desligar a VM
2. Configurações → Armazenamento → controlador SATA → Adicionar Disco
   Rígido → Criar novo disco → VDI, dinâmico, **20 GB**
3. Ligar a VM novamente

📸 **Print:** tela "Detalhes" da VM já com os dois discos →
`evidencias/00-specs-vm-depois-extend.png`

Identificar o novo disco:

```bash
lsblk
```

Deve aparecer como `/dev/sdb`, sem partições.

Extender o Volume Group e o LV escolhido (exemplo com `/home`):

```bash
pvcreate /dev/sdb
vgextend vg_sistema /dev/sdb
vgs                              # conferir se o VFree aumentou ~20G
lvextend -L +20G /dev/vg_sistema/home
xfs_growfs /home
```

> ⚠️ `xfs_growfs` recebe o **ponto de montagem** (`/home`), nunca o device.

Gerar as evidências pós-extend:

```bash
{
  echo "== lsblk -f =="; lsblk -f
  echo "== luksDump =="; cryptsetup luksDump /dev/sda3
  echo "== pvs/vgs/lvs =="; pvs; vgs; lvs
  echo "== findmnt =="; findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS
  echo "== fstab =="; cat /etc/fstab
  echo "== crypttab =="; cat /etc/crypttab
} > evidencias-disco-pos-extend.txt
```

Tirar um novo snapshot: `pos-extend-disco`.

---

## 7. Estrutura final de evidências

```
evidencias/
├── 00-specs-vm-antes-extend.png
├── 00-specs-vm-depois-extend.png
├── 01-resumo-particionamento-anaconda.png
└── disco/
    ├── evidencias-disco.txt
    ├── evidencias-disco-pos-extend.txt
    └── evidencias-sistema-selinux.txt
```

---

## 8. Troubleshooting

**`getenforce` retorna Permissive**
→ `touch /.autorelabel && reboot`, conferir de novo depois do boot. Se
persistir, editar `/etc/selinux/config`, trocar `SELINUX=enforcing`.

**Anaconda tenta colocar `/boot` dentro do LUKS**
→ Apagar a partição e recriar como Standard Partition, fora do LVM e da
criptografia.

**`cryptsetup luksDump` pede senha e trava**
→ Normalmente não pede. Se pedir, rodar o comando sozinho, fora de blocos
`{}`, e colar a saída manualmente.

**`lvextend` retorna "Failed to find logical volume"**
→ Conferir o nome real do LV com `lvs` — o Anaconda pode ter nomeado sem o
prefixo `lv_` (ex: `home` em vez de `lv_home`).

**`lvextend` reclama "not enough free space"**
→ Rodar `vgs` e conferir se o `VFree` aumentou depois do `vgextend`. Se não
aumentou, repetir `pvcreate`/`vgextend` lendo a mensagem de erro completa.

**`xfs_growfs` dá "Invalid argument"**
→ Passar o ponto de montagem (`/home`), não o device.

**Disco novo não aparece no `lsblk`**
→ Confirmar mesmo controlador SATA do disco principal e que a VM foi
**reiniciada** (desligar → ligar), não só pausada.

**VG ficou 100% alocado**
→ Nenhum LV deve usar "resto do disco" — sempre informar tamanho fixo na
criação, deixando espaço livre reservado para snapshot.
