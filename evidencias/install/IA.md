## Uso de IA

Durante o projeto foi utilizado na parte de instalação o Claude para auxilio.

- Organizar o passo a passo do INSTALL.md
	Script: Crie um install.md com o passo a passo para instalação do Alma Linux com as partições especificamente feitas da forma como criei.
	
	Resposta: INSTALL.md
	
	
- Ajudar a resolver erros de comando durante a instalação (LVM e LUKS)
	Script: As partições não estão dentro de vg_sistema me auxilie a corrigir esse erro mantendo tudo de acordo com o que o professor pediu nesta print para criação deste trabalho.
	
	Resposta:
	O que está errado
	Repara no padrão das linhas 8 a 28: pra cada LV (vg_sistema-home, vg_sistema-tmp, vg_sistema-var_tmp, etc.) tem uma sequência separada:

		criar dispositivo   lvmlv      vg_sistema-home
		criar formato        LUKS       vg_sistema-home
		criar dispositivo   luks/dm-crypt   luks-vg_sistema-home   /home

	Isso significa que o Anaconda está criando um container LUKS diferente para cada LV (home, tmp, var_tmp, var_log, var...), não um único container para o VG inteiro. E reparando nas linhas 6-8 (que vimos no print anterior): o sda3 foi formatado direto como physical volume (LVM) sem LUKS nenhum — a criptografia só aparece depois, em cada LV individualmente.

	Isso é diferente do que o trabalho pede. O diagrama de referência diz:

	sda3 ~58 GB → LUKS2 container criptografado → VG vg_sistema (PV = /dev/mapper/cryptlvm)

	Ou seja: um único container LUKS envolvendo o disco inteiro, e o VG vive dentro desse container — não vários containers, um por LV. Isso também quebra uma evidência específica que o professor pede: cryptsetup luksDump /dev/sda3 — com o jeito que está agora, isso vai dar erro, porque /dev/sda3 não é LUKS, é só um PV puro.

	Por que isso aconteceu

	Quando você deixou "Criptografar meus dados" marcado como padrão geral, cada novo ponto de montagem que você criou pegou essa opção individualmente — em vez de criptografar o PV uma vez só e todo LV nascer criptografado por herança (que era a ideia), ele criptografou cada LV, um por um, separadamente.

	Como corrigir

	Clique em "Cancelar e retornar para o particionamento personalizado" (não aceite essa lista). Depois:

	Apague tudo e recomece o particionamento manual (ou, se preferir, pode tentar sem apagar: selecione cada LV um por um, desmarque "Criptografar" em todos, exceto o /)
	Recrie na ordem: /boot/efi e /boot (Standard Partition, sem criptografia) — isso já está certo, não mexe
	Ao criar o primeiro LV (/), marque LVM + Criptografar — só nesse
	Ao criar os LVs seguintes (/var, /var/log, etc.), deixe "Criptografar" DESMARCADO — eles devem herdar a criptografia do PV automaticamente, sem precisar marcar de novo
	Antes de clicar em "Pronto", confira o resumo de novo: agora deve aparecer só uma vez "criar formato LUKS" — ligada ao physical volume (PV) do sda3, não uma vez por LV
	
	
- Organizar a lista de evidências e nomes de arquivo
	Script: Crie um script no qual unificaria os comandos para gerar as evidências e escolha um nome no qual faça sentido com a evidência. 
	
	Resposta:
		O bloco junta tudo com cat e redireciona pra um .txt:
		
			bash
			{
			  echo "== lsblk -f =="; lsblk -f
			  echo "== luksDump =="; sudo cryptsetup luksDump /dev/sda3
			  echo "== pvs/vgs/lvs =="; sudo pvs; sudo vgs; sudo lvs
			  echo "== findmnt =="; findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS
			  echo "== fstab =="; cat /etc/fstab
			  echo "== crypttab =="; cat /etc/crypttab
			} > evidencias-disco.txt
		
			Copie evidencias-disco.txt para a pasta evidencias/ do repositório (saída em texto é preferida a print — pode ser conferida).

			Depois de adicionar o segundo disco e fazer o extend, rode o mesmo bloco de novo e salve como evidencias-disco-pos-extend.txt, para mostrar o antes e o depois.

			Sintoma: cryptsetup luksDump pede senha e trava o bloco acima
			Normalmente não pede (só lê o header). Se pedir, rode esse comando sozinho, fora do bloco {}, e cole a saída manualmente no arquivo.
			Sistema e SELinux

			O mesmo padrão se aplica às evidências de sistema, unificando os comandos num único arquivo:

			bash
			{
			  echo "== os-release =="; cat /etc/os-release
			  echo "== uname -r =="; uname -r
			  echo "== getenforce =="; getenforce
			  echo "== sestatus =="; sestatus
			} > evidencias-sistema.txt

			Copie evidencias-sistema.txt para a pasta evidencias/ do repositório, junto com o evidencias-disco.txt.
		
		
- Ajudar a configurar o SSH pra copiar os arquivos de evidência da VM
	Script: Não estou conseguindo utilizar o SSH, dentro da VM, me ajude a liberar a porta, tendo em mente que estou utilizado o Alma Linux e quero passar os arquivos do linux para meu Windows.

	Resposta:
		Dentro da VM (AlmaLinux):
		sudo systemctl enable --now sshd
		sudo firewall-cmd --add-service=ssh --permanent
		sudo firewall-cmd --reload
		ip a          # anota o IP, mas com NAT isso não importa direto do host
		
		No VirtualBox (host): como sua rede está em NAT, o Windows não enxerga a VM diretamente — precisa criar um redirecionamento de porta:

			1. Configurações da VM → Rede → Adaptador 1 → Avançado → Redirecionamento de Portas
			2. Clique no "+" e crie uma regra:
			Nome: SSH
			Protocolo: TCP
			IP do Hospedeiro: (deixe vazio)
			Porta do Hospedeiro: 2222
			IP do Convidado: (deixe vazio)
			Porta do Convidado: 22
			3. OK
			
		No Windows (PowerShell), pra copiar a pasta de evidências pro seu PC:
			scp -P 2222 -r seu_usuario@127.0.0.1:/home/seu_usuario/evidencias-disco-inicial .
		
	