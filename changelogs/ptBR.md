# QuestTogether — Registro de alterações

<!-- Generated from canonical release notes; do not edit by hand. -->

## 5.16.6

Leia as mesmas notas de lançamento do QuestTogether dentro do jogo, no Discord e no seu idioma preferido nos arquivos de changelog.

### Changelogs consistentes e multilíngues

- O changelog em inglês agora compartilha os mesmos resumos de lançamento e tópicos da janela de boas-vindas e dos anúncios no Discord.
- Os arquivos de changelog estão disponíveis para todos os idiomas compatíveis, com o histórico de lançamentos traduzido existente e uma cópia preservada das notas antigas em inglês escritas manualmente.
- As verificações de lançamento mantêm os arquivos de changelog sincronizados com as notas e traduções canônicas.

## 5.16.5

Um prefixo mais curto mantém os anúncios do grupo compactos.

### Anúncios compactos para o grupo

- O progresso da missão enviado aos membros do grupo sem QuestTogether agora começa com [QT] em vez de [QuestTogether].
- Os anúncios ainda respeitam o limite de mensagens do chat e preservam caracteres completos em todos os idiomas.

## 5.16.4

Mantenha suas configurações de bolha ao sair do Modo de Edição e encontre companheiros de missão próximos em mapas lotados.

### Configurações de bolha continuam salvas

- Fechar o Modo de Edição do HUD agora preserva o tamanho da fonte, a duração de exibição e a posição da sua bolha do QT em vez de revertê-los.
- O painel de bolha do QT agora tem seu próprio botão Salvar Alterações e mensagem de estado salvo. As configurações se aplicam automaticamente; Salvar Alterações define o ponto ao qual Reverter Alterações retorna.
- Depois de salvar e fazer mais ajustes, Reverter Alterações restaura suas últimas configurações salvas do QT.

### Jogadores próximos têm prioridade

- Quando mais de 128 pontos elegíveis disputam espaço no mapa ou minimapa, os jogadores mais próximos têm prioridade com base na distância do seu personagem.
- Quando o cache de 512 localizações fica cheio, jogadores mais próximos são mantidos antes de chegadas mais distantes. Mover e aplicar zoom no mapa não alteram a prioridade de proximidade.
- Essas mudanças mantêm os limites existentes de pontos e de cache sem enviar mensagens de comunicação adicionais.

## 5.16.3

Encontre as configurações de que você precisa com mais facilidade e veja suas preferências do QuestTogether de relance.

### Configurações organizadas em torno de como você joga

- Grupos e Compartilhamento substitui Diversos, reunindo disponibilidade de parceiros, solicitações de entrada e aprovações de compartilhamento de missões.
- Emotes de comemoração agora ficam em Onde Anunciar. A visibilidade no minimapa fica em Geral na página principal, com ferramentas de depuração e nova varredura do registro de missões juntas em Solução de Problemas.
- Comparar Missões do Grupo e Encontrar Parceiros de Missões agora são as primeiras Ações Rápidas. Suas preferências existentes são preservadas.

### Um Status Rápido mais útil

- Veja seu status de parceiro, compartilhamento de localização e preferências de exibição, aprovações de solicitações, saída de anúncios e configurações de placas de identificação de missões e jogadores nas seções vinculadas.
- Verifique seu perfil ativo, a versão instalada e qualquer versão mais recente detectada. Quando o QT estiver desativado, o resumo identifica claramente as configurações como preferências salvas.
- Clique no cabeçalho de uma seção para abrir suas configurações. O resumo se expande para caber no texto e permanece atualizado enquanto a página estiver aberta.

## 5.16.2

Reconheça jogadores do QuestTogether pelos tooltips deles e encontre parceiros de missões com mais facilidade.

### Tooltips de jogadores do QuestTogether

- Passe o mouse sobre o personagem, a barra de nome ou o quadro de unidade de um jogador QT para ver “Este jogador está usando QuestTogether.” Jogadores procurando parceiros para fazer missões também mostram esse status e um logotipo QT brilhante.
- A seção QT acompanha a largura e a escala do tooltip, fica afastada da barra de vida e se move para cima do tooltip quando o espaço abaixo é limitado.

### Um brilho de parceiro mais visível

- O brilho dourado da barra de nome agora se estende duas vezes mais ao redor do logotipo, mantendo o logotipo em si do mesmo tamanho.
- Ícones e brilhos refletem usuários reais do QT e o status atual deles de procura por parceiros.

## 5.16.1

Encontre parceiros de missões com mais facilidade e veja em qual missão eles estão focando.

### Um brilho de parceiro mais forte

- Jogadores procurando parceiros para fazer missões agora têm um brilho dourado mais forte ao redor do logotipo do QT na placa de identificação, com uma pulsação suave. O logotipo em si permanece estável.

### Veja a missão atual deles

- Passe o mouse sobre o ponto no mapa ou minimapa de um jogador procurando parceiros para fazer missões para ver a missão super-rastreada dele — a única missão selecionada para navegação. Ambos os jogadores precisam desta atualização.
- As informações da missão são atualizadas a cada cerca de 20 segundos. Elas só são compartilhadas enquanto Procurando Parceiros para Missões e o compartilhamento de localização estiverem ativados.
- Os nomes das missões usam o idioma do seu cliente quando disponível, com o título ou ID da missão do remetente como alternativa. Versões mais antigas do QT mantêm seus pontos e indicadores de parceiros existentes.

## 5.16.0

O QuestTogether agora oferece suporte a todos os idiomas do WoW e pode exibir as atualizações de missões de outros jogadores no idioma do seu cliente.

### Jogue em mais idiomas

- Menus, configurações e notas de atualização agora oferecem suporte a todas as localidades de idioma do WoW: inglês, alemão, francês, espanhol europeu, espanhol latino-americano, português do Brasil, russo, italiano, coreano, chinês simplificado e chinês tradicional.
- O espanhol latino-americano agora tem seu próprio texto em vez de compartilhar o espanhol europeu.

### Progresso de missão localizado

- Eventos de missão compatíveis de jogadores QT atualizados podem aparecer no idioma do seu cliente nos registros e balões de bate-papo do QT, usando títulos de missões locais quando disponíveis e os números reais de progresso do remetente.
- Quando uma descrição traduzida do objetivo não puder ser escolhida com segurança, o QT usa um número de objetivo localizado com contagens, porcentagens, conclusão ou status de progresso.
- Versões antigas do QT e o bate-papo público do grupo mantêm o texto do remetente. Quando o WoW não puder fornecer um título de missão local, o QT mantém o título de origem ou mostra o ID da missão. Eventos no mesmo idioma mantêm o texto nativo detalhado.

### Ajustes nos títulos de missões

- A comparação de missões agora dá preferência ao título local da missão quando disponível.
- Títulos de missões localizados com pontuação não ASCII permanecem clicáveis com mais confiabilidade.

## 5.15.0

Peça para entrar em um grupo de missões diretamente pelo menu de um jogador do QuestTogether.

### Entre em um grupo de missões

- Jogadores do QT que já estão em grupo agora mostram Pedir para entrar em vez de Convidar quando há informações recentes do grupo. Ambos precisam desta atualização; quem envia o pedido deve estar sem grupo.
- O destinatário pode enviar um convite normal do WoW ou recusar. Ele precisa ter permissão para convidar e espaço em um grupo normal. Você ainda aceita o convite normal para entrar.

### Convites automáticos opcionais

- Duas novas opções aprovam automaticamente pedidos de amigos do seu personagem ou de outros jogadores enquanto você procura parceiros de missão. Ambas vêm desativadas e aparecem no pedido e nas configurações Diversos. Amigos de conta Battle.net não estão incluídos.
- Os pedidos expiram e respeitam a lista de ignorados, mudanças no grupo e restrições do jogo. O QT nunca sai do seu grupo atual nem aceita convites por você.

## 5.14.1

Os anúncios de grupo agora mostram o nome completo do QuestTogether.

### Bate-papo do grupo

- O prefixo dos anúncios no bate-papo do grupo mudou de [QT] para [QuestTogether], facilitando que outros jogadores encontrem o addon.

## 5.14.0

O QuestTogether agora fala mais cinco idiomas e ajuda você a manter informados os integrantes do grupo que não usam QT.

### Jogue no seu idioma

- A interface agora está disponível em alemão, francês, espanhol, português do Brasil e russo. O QuestTogether acompanha o idioma do jogo e usa o inglês quando necessário.
- Configurações, menus, dicas, comparações de missões e notas de atualização estão traduzidos. Os nomes de missões e textos de progresso recebidos de outros jogadores permanecem no idioma original.
- Encontre os anúncios de atualização traduzidos nos cinco canais de registro de alterações por idioma do nosso Discord.

### Mantenha todo o grupo informado

- Uma nova opção de canais de anúncios envia seus anúncios de eventos habilitados para o bate-papo do grupo quando algum integrante ainda não foi reconhecido como usuário do QT. Ela vem ativada e pode ser desativada nas configurações.
- Também funciona em grupos de instância formados automaticamente. Não se aplica ao jogo solo nem a raides, e os anúncios de outros jogadores nunca são retransmitidos.
