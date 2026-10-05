# QuestTogether — Registro de alterações

<!-- Generated from canonical release notes; do not edit by hand. -->

## 6.1.0

Encontre grupos no mapa, veja quem está fazendo missões junto e peça para entrar por meio de qualquer membro do grupo. As dicas de jogadores agora colocam os detalhes do grupo em destaque.

### Veja quem está fazendo missões junto

- Jogadores agrupados agora têm um pequeno emblema de duas pessoas nos pontos do mapa e do minimapa. Passe o mouse sobre um membro do grupo para dar aos companheiros dele um contorno branco, escurecer pontos não relacionados e mostrar uma coroa no líder. Os brilhos dourados de Procurando Parceiros para Missões continuam visíveis.
- As dicas de jogadores listam os membros do grupo com pontos e nomes nas cores das classes, com o líder coroado primeiro. Grupos de até cinco listam todos os membros; grupos maiores mostram apenas o líder. Esses detalhes também aparecem ao passar o mouse sobre nomes de jogadores no registro do QuestTogether.
- Seu próprio grupo usa a lista do jogo. Detalhes de grupos remotos são carregados de pares atualizados do QuestTogether quando necessário, com resultados em cache e solicitações dosadas para manter o tráfego do canal baixo. Clientes mais antigos mantêm seus pontos normais e informações básicas de tamanho do grupo; os detalhes completos de grupos remotos exigem um par atualizado.

### Solicitações para entrar podem chegar ao líder do grupo

- Você pode pedir para entrar por meio de um membro do grupo que não pode convidar você. Se o líder dele estiver usando o QuestTogether e puder convidar, a solicitação será redirecionada ao líder usando as configurações normais de confirmação e aprovação automática.
- Se não houver confirmação de que o líder usa o QuestTogether, o membro poderá anunciar “[QT] PlayerName está pedindo para entrar no grupo.” no bate-papo do grupo quando os anúncios no bate-papo do grupo estiverem ativados. Alguém com permissão para convidar terá que convidar você manualmente.
- O solicitante e o membro que encaminha precisam desta atualização para solicitações redirecionadas. As verificações existentes de grupo cheio, restrições, ignorados, expiração e frequência de solicitações ainda se aplicam.

### Dicas de jogadores mais limpas

- As informações do grupo agora ficam logo abaixo da linha de nível, raça e classe, com linhas de membros compactas e espaço entre as seções. Os emblemas da Aliança e da Horda têm o dobro do tamanho.
- A versão do addon aparece por último no formato mais curto vX.Y.Z. Quando a idade de uma localização é mostrada, Última atualização fica diretamente acima da versão.
- As contagens de missões rastreadas foram removidas das dicas de jogadores e do botão do minimapa. O título da missão ativa para jogadores procurando parceiros para missões ainda é mostrado.

## 6.0.2

Navegue pelas atualizações anteriores do QuestTogether no seu idioma, com melhor recuperação de nomes de missões para anúncios de conclusão.

### Ver notas de atualização anteriores

- A janela de boas-vindas agora tem botões Mais antigas e Mais recentes, um atalho para a Mais recente e um seletor de Histórico mostrando versões e datas de lançamento. Ao abrir as notas de atualização, elas começam na versão mais recente.
- O histórico inclui todas as versões publicadas anteriormente, incluindo os primeiros betas. Todas as notas históricas são traduzidas para todos os idiomas de WoW compatíveis e incluídas nos changelogs correspondentes do repositório.
- Os botões de navegação ficam desativados quando não há para onde ir. Navegar por notas mais antigas não altera qual atualização você reconheceu; pop-ups automáticos ainda aparecem apenas para atualizações principais e secundárias. Abra a janela a qualquer momento com /qt notes.

### Títulos de conclusão de missões

- Quando uma missão sai do seu registro antes que o QuestTogether tenha um título utilizável, os anúncios de conclusão agora tentam consultar o título da missão disponível no jogo antes de recorrer a um ID de missão. Um título recuperado é preservado independentemente da ordem dos eventos de entrega e remoção.
- Os anúncios ainda usam o texto do remetente quando o seu cliente não consegue resolver um título local. Se nenhum dos clientes tiver um nome disponível, o ID da missão continua sendo a alternativa. A recuperação aprimorada do lado do remetente se aplica quando o remetente atualiza.

## 6.0.1

As celebrações agora permanecem com jogadores que você realmente consegue ver por perto.

### Correções de celebrações próximas

- Reações a outro jogador concluindo uma missão ou subindo de nível agora exigem uma unidade de jogador correspondente e visível. Coordenadas do mapa ou apenas um nome não acionam mais um emote, inclusive quando devlogall está ativado.
- Emotes recebidos devem corresponder à própria lista de celebrações do QuestTogether. Emotes não listados, incluindo mountspecial e gritos de facção, são ignorados sem escolher um substituto.
- Suas próprias celebrações de conclusão de missão e de subida de nível mantêm o comportamento e as configurações existentes.

## 6.0.0

QuestTogether 6.0 se prepara para o lançamento do Forever com um sistema de comunicação projetado para reduzir o tráfego em segundo plano conforme a comunidade cresce.

### Atividade local, descoberta mundial

- Anúncios de missões e atualizações frequentes de jogadores agora usam canais de zona. Anúncios do grupo ainda chegam ao seu grupo além dos limites de zona.
- Os pontos de jogadores continuam disponíveis pelo mundo, com atualizações em segundo plano mais lentas. Abrir outra zona no mapa-múndi assina temporariamente suas atualizações.
- O chat de texto do QT permanece no canal global do QuestTogether. Sua configuração de chat Global ou Apenas Zona ainda controla quais mensagens você vê.

### Menos tráfego em segundo plano

- Presença, versão, contagens de missões, status de parceiro e localização são agrupados em atualizações compactas. Zonas lotadas são atualizadas com menos frequência para reduzir o tráfego.
- Anúncios são espaçados e têm prioridade sobre atualizações em segundo plano. Respostas de ping são distribuídas para evitar uma enxurrada de respostas. O WoW ainda pode atrasar a entrega pelo canal; esta atualização não garante mensagens instantâneas.
- As dicas de interface de jogadores mostram a idade de localizações mais antigas. O diagnóstico agora informa contagens de mensagens, limitação e atrasos de anúncio relatados pelo remetente.

### Uma grande atualização durante a beta

- Estamos fazendo esta mudança maior de comunicação agora em antecipação ao lançamento do Forever. A beta é o melhor momento para tomar essas decisões fundamentais, antes que mais jogadores dependam do comportamento antigo.
- A versão 6.0 sai do QuestTogetherAnnounce1 e não envia nem recebe mais nesse canal legado. Ela usa QuestTogether para chat global e descoberta, além de canais de zona para atividade local.
- O QuestTogether mantém seus canais depois dos seus outros canais de chat, com o canal principal de chat antes dos canais de zona. Suas preferências de compartilhamento de localização, lista de ignorados e anúncios são preservadas.

### Compatibilidade com versões antigas

- Por favor, atualizem juntos. Versões antigas não conseguem ler as novas atualizações agrupadas de jogadores nem ouvir os novos canais de zona, então jogadores com versões diferentes podem perder pontos no mapa, status de parceiro e anúncios de missões próximas.
- Jogadores usando apenas o canal legado não podem mais ser descobertos por esse canal na 6.0. Algumas trocas com versões 5.x mais novas ainda podem funcionar pelo canal global compartilhado ou por um grupo, mas isso é compatibilidade parcial, não a experiência completa.
- O /qt ping manual ainda usa o canal global. Ele pode ouvir clientes antigos compatíveis lá, mas é uma ferramenta de descoberta de melhor esforço, não uma contagem completa de todos que usam o QuestTogether.

## 5.17.2

O chat do QT fica mais fácil de distinguir dos anúncios de missões.

### Texto branco no chat do QT

- Mensagens de jogadores no chat do QT agora usam texto branco no registro de bate-papo e nos balões sobre a cabeça.
- Os nomes dos jogadores mantêm as cores de suas classes, e os anúncios de missões mantêm o texto amarelo.

## 5.17.1

Veja mais sobre seus companheiros de missões e confira o status da missão diretamente nas dicas de chat.

### Dicas de jogadores mais úteis

- As dicas de nome do jogador e de pontos no mapa agora mostram quantas missões o QuestTogether está monitorando, além de Solo ou Grupo de N. Sua própria dica usa seu estado local atual.
- A dica do minimapa agora conta as missões monitoradas pelo QuestTogether, correspondendo ao anúncio de inicialização em vez de contar apenas as missões acompanhadas no rastreador do WoW.
- Contagens de missões remotas e tamanhos de grupo exigem um par atualizado. Elas são atualizadas aproximadamente a cada 80 segundos por meio das mensagens de pulsação existentes, sem mensagens extras; relatórios ausentes ou desatualizados aparecem como desconhecidos. Versões mais antigas continuam recebendo anúncios de versão compatíveis.

### Status da missão ao passar o mouse

- Passe o mouse sobre o nome de uma missão nos registros do QT para ver seu status da missão, se ela pode ser compartilhada, o ID da missão e o progresso dos objetivos rastreados localmente em uma dica ao lado do cursor.
- O item de menu Status foi removido. Clicar no nome de uma missão ainda abre Compartilhar, Abrir no Diário de Missões, Comparar Missões do Grupo e a ação de destino da janela de registro.
- Os novos rótulos das dicas estão traduzidos para todos os idiomas compatíveis. Os detalhes da missão refletem seu próprio progresso, não a etapa da missão do remetente.

## 5.17.0

Diga olá no bate-papo do QT, encontre parceiros de missões pela sua zona e descubra detalhes de jogadores e configurações mais claros.

### Converse com outros jogadores do QuestTogether

- Digite /qt <text>, ou escolha Enviar mensagem de bate-papo do QT no menu do minimapa. As conversas aparecem nos registros do QT e em balões acima de jogadores próximos com um ícone de balão de fala; os comandos de barra existentes continuam funcionando.
- Escolha bate-papo Global (o padrão), Somente Zona, ou oculte totalmente o bate-papo do QT. Somente Zona exige uma localização compartilhada recente do remetente; Global não.
- O novo canal QuestTogether funciona junto com QuestTogetherAnnounce1 durante a transição. O QT coloca ambos depois dos seus outros canais quando compatível, com QuestTogether primeiro; o bate-papo digitado usa apenas o novo canal.

### Encontre parceiros de missões

- Ativar Procurando parceiros de missões anuncia sua busca por toda a sua zona com um ícone QT com brilho dourado e um sorriso. A entrega por toda a zona exige compartilhamento de localização e respeita as preferências de anúncio; desativar permanece silencioso.
- Controle essas mensagens em O que anunciar. Uma recarga de 30 segundos limita anúncios repetidos, enquanto seu status e brilho ainda são atualizados imediatamente. Você também pode escolher parar de procurar automaticamente ao entrar em um grupo; isso começa desativado.
- Shift-clique no botão do minimapa para alternar sua busca por parceiros. Um anel dourado mais brilhante e pulsante destaca sua busca ativa sem cortar o logotipo.

### Escolha seu alcance e veja mais detalhes dos jogadores

- O Alcance Próximo agora vai de 5% até Zona Inteira, com padrão de 25%. Ele dimensiona a distância pela sua zona atual; membros do grupo e jogadores diretamente visíveis mantêm o comportamento existente.
- Passe o mouse sobre nomes nos registros do QT para ver a mesma dica aprimorada dos pontos no mapa: nome colorido pela classe, nível, raça, classe, emblema da facção, status de parceiro, missão rastreada quando disponível e versão do QT. As dicas de nome agora aparecem ao lado do cursor.
- A dica do seu próprio nome agora mostra sua missão super-rastreada atual enquanto procura parceiros. Clientes atualizados anunciam versões aproximadamente a cada 40 segundos usando as mensagens de pulsação existentes; clientes mais antigos mantêm a programação anterior.

### Controles e anúncios mais claros

- A dica do minimapa agora mostra sua versão do QT, status de parceiro, escopo do bate-papo, contagem de missões observadas, alcance próximo e status de compartilhamento de localização.
- Os controles das configurações agora têm explicações traduzidas ao passar o mouse, incluindo menus suspensos, controles deslizantes, ações de perfil e controles de cor.
- Quando seu cliente não consegue resolver um título de missão localizado, os anúncios preservam o texto original do remetente tanto nos registros quanto nos balões, em vez de mostrar um número genérico de missão. A renderização localizada é retomada em anúncios posteriores assim que o título estiver disponível.

## 5.16.7

Leia as mesmas notas de lançamento do QuestTogether dentro do jogo, no Discord e no seu idioma preferido nos arquivos de changelog.

### Changelogs consistentes e multilíngues

- O changelog em inglês agora compartilha os mesmos resumos de lançamento e tópicos da janela de boas-vindas e dos anúncios no Discord.
- Os arquivos de changelog estão disponíveis para todos os idiomas compatíveis, com o histórico de lançamentos traduzido existente e uma cópia preservada das notas antigas em inglês escritas manualmente.
- As verificações de lançamento mantêm os arquivos de changelog sincronizados com as notas e traduções canônicas.

## 5.16.6

Veja rapidamente quando você está procurando parceiros para fazer missões.

### Um lembrete brilhante no minimapa

- Seu botão do QuestTogether no minimapa agora pulsa com o mesmo brilho dourado do logotipo das placas de nome dos jogadores enquanto Procurando Parceiros para Missões está ativado.
- O brilho acompanha seu status de parceiro e para quando o QT é desativado ou quando o botão do minimapa está oculto. Seu botão e logotipo mantêm o tamanho atual.

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

## 5.13.1

Esta atualização de manutenção melhora a recuperação das placas de missões, limpa balões e logotipos de jogadores obsoletos e mantém as configurações e a janela de depuração se comportando de forma consistente.

### Placas de missões e indicadores de jogadores

- Ícones de missões e tons de vida se recuperam corretamente depois que visualizações restritas são fechadas. Varreduras de missões adiadas mantêm seu tempo de estabilização, e dados de tooltip temporariamente ausentes mantêm seu limite de novas tentativas.
- Balões de anúncio são limpos quando a placa de um jogador desaparece ou é reutilizada durante o combate. Quadros protegidos ou proibidos aguardam uma limpeza segura.
- Localizações no mapa e presença de jogadores se recuperam após desativar o QuestTogether, mudar de zona e ativá-lo novamente. Jogadores que saíram não recuperam mais um logotipo QT por causa de retiradas tardias de localização ou status de parceiro.

### Correções de configurações e janela

- A caixa Procurando parceiros para fazer missões permanece sincronizada quando o status muda por comandos, menus ou configurações de perfil.
- A janela de depuração termina com segurança gestos de arrastar e redimensionar interrompidos quando as restrições são suspensas, mesmo depois de ter sido ocultada.

### Melhorias de confiabilidade

- Testes reforçados detectam acesso a quadros proibidos mesmo quando um erro é capturado internamente.
- As verificações de lançamento agora recusam publicar enquanto mudanças de implementação permanecem sem commit, ajudando a garantir que as correções realmente cheguem ao download.

## 5.13.0

Encontre parceiros para fazer missões de relance com pontos no mapa e logotipos de jogadores destacados, configurações de localização mais simples e lembretes quando outro jogador tiver uma versão estável mais recente do QuestTogether.

### Encontre parceiros para fazer missões

- Jogadores procurando parceiros para fazer missões têm um brilho dourado suave ao redor dos pontos do mapa e do minimapa coloridos pela classe.
- O logotipo do QuestTogether na placa de identificação deles recebe um brilho dourado suave. Os destaques desaparecem quando o status é desativado ou expira.
- As configurações de Localizações de Jogadores incluem Mostrar apenas jogadores procurando parceiros para fazer missões. Ela começa desativada e filtra ambos os mapas quando ativada.
- A janela Novidades do jogo mostra logotipos e pontos de mapa normais e brilhantes lado a lado. Brilho dourado significa procurando parceiros para fazer missões.

### Configurações de localização mais simples

- Compartilhar minha localização e Mostrar outros jogadores se aplicam ao mapa-múndi e ao minimapa.
- Ambas as opções começam ativadas para novos perfis. Opções de não compartilhar localização existentes são preservadas ao atualizar.

### Lembretes de nova versão

- O QuestTogether percebe quando outro jogador informa uma versão estável mais recente do addon e imprime um lembrete de atualização na janela de chat do QuestTogether escolhida por você.
- O lembrete é salvo entre personagens e aparece uma vez a cada recarregamento até você instalar a versão detectada ou uma mais recente. Versões alfa e beta não acionam lembretes.
- Anúncios de versão são pequenos e pouco frequentes. O QuestTogether também reconhece informações de versão em respostas de ping existentes.

## 5.12.0

Encontre pessoas para fazer missões usando o novo status Procurando parceiros para fazer missões. Esta atualização também melhora a visibilidade dos tooltips do minimapa e separa o comportamento do Modo de Guerra e dos reinos do Retail do Forever.

### Procurando parceiros para fazer missões

- Informe a outros usuários do QuestTogether que você quer companhia. Seu status aparece no menu do seu jogador e nos tooltips dos pontos do mapa; ele não ativa compartilhamento de localização nem envia convites.
- Alterne o status pelo menu do minimapa, Configurações > Diversos ou /qt lfg. Use /qt lfg on, off ou status para definir ou verificar. Ele começa desativado e é salvo por perfil.
- O status de parceiro expira quando as atualizações param. Jogadores ignorados são excluídos, e desativar o QuestTogether pausa seu anúncio.

### Retail e Forever

- O Forever não mostra mais o Modo de Guerra nos tooltips dos pontos de jogadores, nos detalhes de localização de missões nem na saída de ping. Pings do Forever também omitem rótulos de reino, preservando os nomes completos dos jogadores.
- Atualizações de missões próximas no Forever não exigem mais informações de Modo de Guerra do Retail. Os pontos no mapa permanecem visíveis entre fases para que você encontre pessoas com quem formar grupo.
- O Retail usa o estado ativo do Modo de Guerra quando disponível. Modo de Guerra desconhecido ou incompatível não é mais informado como Desativado.

### Pontos de jogadores mais estáveis

- Coordenadas brevemente ausentes não removem mais seu ponto imediatamente. As últimas posições informadas permanecem por até dois minutos, e informes mais antigos mostram a idade no tooltip. Opções de não compartilhar ainda são retiradas imediatamente quando a comunicação está disponível.
- Transmissões de movimento são limitadas a uma vez a cada dez segundos, reduzindo o tráfego de localização. Batimentos estacionários continuam a cada vinte segundos para manter clientes mais antigos compatíveis.
- O cache de localização agora mantém até 512 jogadores. Cada mapa ainda desenha no máximo 128 pontos visíveis, e jogadores fora do mapa exibido não consomem mais esse limite de desenho.

### Logotipos de jogadores confiáveis

- Corrige logotipos ausentes nas placas de identificação de jogadores aliados nos clientes Forever e Retail atuais lendo a configuração atual de visibilidade de jogadores aliados.
- Logotipos posicionados à esquerda se movem para fora para abrir espaço para bônus visíveis e depois retornam à posição normal quando os bônus desaparecem.
- Todas as mensagens compatíveis do QuestTogether agora identificam seu remetente. Um cache limitado lembra jogadores durante a sessão atual da IU, então batimentos perdidos não removem mais seus logotipos. Saídas explícitas e jogadores ignorados ainda são removidos; nenhuma mensagem extra é enviada.

### Polimento do minimapa

- O tooltip do minimapa do QuestTogether agora usa uma camada de tooltip independente para poder aparecer sobre a IU da barra de ações. Ele se oculta quando o botão fica indisponível ou as restrições começam.

## 5.11.0

O QuestTogether agora adiciona localizações de jogadores, logotipos nas placas de jogadores, comparações de missões direcionadas e feedback e suporte mais fáceis pelo Discord. As configurações permitem escolher o que você compartilha e o que vê enquanto o progresso de missões permanece coordenado com outros usuários do QuestTogether.

### Encontre jogadores do QuestTogether por perto

- Mostre o logotipo de pergaminho ao lado de jogadores aliados do QuestTogether quando as placas de identificação aliadas do WoW estiverem ativadas. Placas de Jogadores ficam ativadas por padrão, com a posição Esquerda espaçada; escolha Esquerda, Direita, Acima ou Prefixo sem mudar as cores da barra de vida.
- Pontos de jogadores coloridos pela classe podem aparecer no mapa-múndi e no minimapa para jogadores que compartilham sua localização. Passe o mouse sobre um ponto para ver nome, facção, raça, classe e nível; clique nele para abrir o menu de jogador do QuestTogether.
- Localizações de Jogadores tem controles separados de compartilhamento e visualização para o mapa-múndi e o minimapa, e todos os quatro começam ativados. A presença dos logotipos nas placas de jogadores pode continuar mesmo quando ambos os controles de compartilhamento de localização estão desativados.
- As localizações são atualizadas periodicamente e desaparecem quando expiram. Ambos os jogadores precisam do addon atualizado; um ponto não garante que vocês compartilhem a mesma fase ou camada.

### Compare um jogador ou o grupo inteiro

- A ação Comparar Missões do menu de jogador agora compara apenas você e o jogador selecionado, incluindo pares do QuestTogether alcançáveis fora do grupo. A comparação do grupo inteiro continua disponível pelo menu do minimapa, menus de nomes de missões e /qt compare.
- Compartilhamento de missões e pedidos de compartilhamento continuam sendo apenas para o grupo. Comparações direcionadas explicam quando um grupo é necessário para compartilhar e quando o jogador selecionado precisa do QuestTogether para responder.
- Se um pedido de compartilhamento já estiver aguardando outro jogador, a comparação agora mostra por quem está esperando depois que você troca de alvo.

### Feedback e suporte

- A janela de boas-vindas e a página principal de configurações agora incluem Discord — Feedback e Suporte. Ela abre um convite copiável quando disponível, ou imprime o convite no chat se a janela de link não puder abrir.

### Correções e polimento

- Jogadores ignorados agora são filtrados de forma mais completa. Novos registros, balões, pontos, comparações e trabalhos de compartilhamento são suprimidos, enquanto balões e localizações existentes são limpos quando a lista de ignorados muda.
- Corrigidas placas de missões falsas causadas por limites de tooltip indisponíveis que correspondiam ao texto de objetivo de outra missão.
- Desativar o compartilhamento do mapa ou minimapa agora tenta novamente a atualização após falhas temporárias de comunicação. Desativar ambas as opções de compartilhamento também remove detalhes de localização de outras atualizações do addon.
- Logotipos de jogadores são limpos corretamente quando a presença de um jogador expira pouco antes de ele sair. Sussurrar a partir de pontos do mapa abre sua janela de chat, e mudar o destino do registro em Configurações fica indisponível durante restrições.

## 5.10.0

O QuestTogether compartilha o progresso de missões com seu grupo e jogadores próximos. Use o botão do minimapa para configurações, comparações de missões do grupo, seu diário de missões e estas notas mais recentes.

### Compare e compartilhe missões do grupo

- Abra Comparar Missões do Grupo pelo minimapa ou pelos menus de missões e jogadores, ou digite /qt compare. Veja quem tem cada missão e até onde todos progrediram.
- Todas as missões do grupo aparecem por padrão. Marque Ocultar missões que eu não tenho para focar nas missões do seu próprio diário.
- Peça missões compartilháveis aos membros do grupo usando o addon atualizado. Pedidos solicitam permissão por padrão; compartilhamento automático é uma configuração opcional.
- Comparações se recuperam após restrições de mapa ou combate. Atualizações substituem respostas mais antigas, e recargas e falhas de pedidos explicam quando você pode tentar novamente.

### Atalhos e menus de missões

- Arraste o botão em forma de pergaminho do minimapa para reposicioná-lo. O menu dele abre configurações, comparações, o diário de missões, notas de atualização e o controle de destino da janela de registro. Oculte-o pelo menu e restaure-o nas configurações de Diversos.
- Menus de nomes de missões oferecem Status, Compartilhar, Abrir no Diário de Missões e Comparar Missões do Grupo. Ações de compartilhamento e diário verificam novamente a missão atual e as restrições ao serem clicadas.
- Links de status de missões mantêm seus títulos intactos depois que uma missão sai do seu registro. A caixa de compartilhamento automático agora segue configurações salvas e mudanças de perfil.

### Ajuda e notas mais recentes

- Leia as boas-vindas e as notas de atualização mais recentes em uma janela própria em vez de mensagens repetidas no chat. Escolha Notas de Atualização no menu do minimapa ou na página principal de Configurações, ou use /qt notes, /qt changelog ou /qt patchnotes.
- A janela de notas abre automaticamente para atualizações maiores e menores. Atualizações de correção ainda incluem notas novas sem abrir a janela automaticamente.
- Use /qt help para comandos normais e /qt help debug para prévias, diagnósticos e comandos de desenvolvedor.

## 5.9.2

Clique com o botão esquerdo ou direito no nome de uma missão no registro do QuestTogether para abrir seu menu, com Status primeiro e Compartilhar em segundo. Compartilhar usa a entrada atual do registro de missões sem alterar a missão selecionada pela Blizzard, e fica indisponível quando você está solo, quando há restrição ou quando a missão não pode ser compartilhada. Após um separador, a opção final move os registros do QuestTogether entre a janela principal e janelas separadas, correspondendo ao menu de nome do jogador do QT.

### Alterações nesta versão

- Torna os nomes de missões em mensagens de status clicáveis, incluindo títulos de fallback dos registros de outros jogadores. Preserva links de missões existentes ao formatar comparações de missões concluídas, para que os detalhes de status não se tornem parte de um segundo link quebrado.
- Validação: 521 testes passam em ordem normal e reversa no Lua 5.1 e 5.2. Todos os seis perfis de API de cliente, verificações de sintaxe Lua e shell, verificação exata da libchev e verificações de diff passam. O comportamento de menus no cliente ao vivo, a entrega de compartilhamento de missões e a validação de taint no nível do motor permanecem separados.

## 5.9.1

Corrige o rastreamento de missões, a visibilidade de placas de missões, anúncios de áreas de tarefa, confiabilidade da comunicação e ações do usuário identificadas na auditoria abrangente.

### Alterações nesta versão

- Impede que blocos de missões de dicas não relacionadas tomem emprestado texto de objetivo compartilhado. Preserva progresso válido do grupo e recupera placas após alterações de mapa, instância, lista do grupo e missões.
- Mantém missões recém-aceitas e varreduras iniciais pendentes até que dados legíveis cheguem. Preserva marcos de objetivos, classificação de tarefas e estado de localização desconhecida sem saídas falsas ou entradas duplicadas.
- Melhora anúncios localizados e comparações de missões, incluindo limites de payload, ritmo, novas tentativas, cancelamento e relatório de possibilidade de compartilhamento.
- Respeita falhas nativas de ponto de referência sem rastrear um marcador antigo. Recusa cliques restritos enquanto desativado, em vez de perder trabalho enfileirado.
- Faz com que testes de balão sejam pré-visualizações locais e aceita nomes completos do Forever ou nomes entre aspas, preservando a identidade exata do jogador.
- Corrige ativação/desativação e tratamento de perfis, abertura do Modo de Edição do HUD, emotes de comemoração aprovados e diagnósticos.
- Fortalece o isolamento de testes seguro para cliente ao vivo e a cobertura de regressão, corrige suposições de teste incorretas e faz o CI propagar falhas de sintaxe Lua.
- Validação: 516 testes passam em ordem normal e reversa no Lua 5.1 e 5.2. Todos os seis perfis de API de cliente, verificações de sintaxe, verificação exata da libchev e verificações de diff passam. A renderização no cliente ao vivo, a entrega entre dois clientes e a validação de taint no nível do motor permanecem separadas.

## 5.9.0

Comemora seus aumentos de nível e os de jogadores do QuestTogether próximos com emotes sincronizados. Adiciona alternâncias separadas de emote de aumento de nível, ativadas por padrão, ao lado das configurações de emote de conclusão de missão em Diversos. Reações próximas respeitam o escopo de jogadores e as regras de proximidade existentes.

### Alterações nesta versão

- Lembra a conclusão confirmada de objetivos de missão por tipo de criatura, bem como por aparecimento individual. Mobs que aparecem durante o combate permanecem sem marcação quando os dados de dica estão indisponíveis, mesmo que um aparecimento anterior tenha sido armazenado em cache como necessário. Objetivos novos e inacabados podem restaurar o destaque; alterações no estado da missão limpam a memória de conclusão. Dados de dica parciais ou inacessíveis nunca são tratados como prova de que todos terminaram.
- Limpa ícones de missão das placas de identificação e a coloração da vida imediatamente quando o tag de um mob é negado, inclusive durante o combate. Escuta alterações de posse e verifica novamente os tags em atualizações de vida e ameaça.
- Detecta mobs de missão encontrados recentemente durante combate comum em mundo aberto usando dados legíveis da dica da unidade. Atualiza placas quando elas retornam de trás da câmera, tornam-se seu alvo ou recebem o cursor do mouse. Tenta novamente quadros atrasados, GUIDs e linhas de missão em dicas com um orçamento limitado por unidade, cancela trabalho obsoleto quando unidades são removidas e restaura coloração e ícone juntos. Preserva proteções de mapa, instância, dados inacessíveis e quadros protegidos; a descoberta em combate não invoca o Questie nem a interface oculta de dicas.
- Validação: 374 testes offline passam em ordem normal e reversa no Lua 5.1 e 5.2. Seis perfis de API de cliente, verificações de sintaxe Lua, verificação exata de biblioteca e verificações de diff passam. Regressões do cache de conclusão reproduziram o bug antes da correção. A jogabilidade ao vivo e a validação de taint no nível do motor permanecem separadas.

## 5.8.6

Protege nomes de personagens, nomes de classes, títulos de missões e cores de classe personalizadas contra valores de API inacessíveis ou malformados. Valida dados opcionais de integração com TomTom e Questie antes de usá-los e para de ler linhas de dicas do Questie ao encontrar dados inacessíveis. Normaliza a visibilidade de balões e o estado do modo de edição para booleanos antes de passá-los aos controles da interface.

### Alterações nesta versão

- Consolida o manipulador de evento de tela de carregamento, remove argumentos privados não usados e um ramo não usado de enumeração de restrição, e esclarece o tratamento de callbacks e valores retornados. Mantém intactos os fallbacks de clientes modernos/legados e a revisão exata da biblioteca privada.
- Validação: 336 testes passam em ordem normal e reversa no Lua 5.1 e 5.2, com verificações de adaptadores expandidas em seis perfis de cliente. Novas regressões falham contra a implementação anterior. Análise Lua, verificação exata de biblioteca e verificações de diff passam. Revisados os diagnósticos restantes de Ketho WoW API/LuaLS, incluindo uma passagem separada sem mocks de cliente offline; achados retidos têm motivos específicos de compatibilidade, proteção, callback, biblioteca ou fixture. A validação de jogabilidade ao vivo no Retail e no Forever permanece separada.

## 5.8.5

Corrige a descoberta de tarefas/missões mundiais no mapa em clientes modernos lendo questID de C_TaskQuest.GetQuestsOnMap, mantendo a API legada e o campo questId para clientes mais antigos. Prefere C_ChatInfo.PerformEmote para que emotes de conclusão funcionem quando globais obsoletos estiverem desativados; lida com segurança com APIs de emote ausentes ou com falha.

### Alterações nesta versão

- Remove um cálculo não usado de assinatura da lista do grupo e variáveis locais não usadas. Estende verificações offline de cliente para cobrir APIs modernas e legadas de tarefas/emotes, precedência de API, dados de missão inacessíveis e APIs ausentes/com falha. Validação: 334 testes passam em ordem normal e reversa no Lua 5.1 e 5.2, além das verificações de API expandidas em seis perfis de cliente, análise Lua e verificação exata de biblioteca. A validação de jogabilidade no Retail e no Forever permanece separada das verificações offline.

## 5.8.4

Manutenção do repositório: mantém notas de desenvolvimento local fora do código-fonte rastreado e dos pacotes de lançamento. O comportamento de jogabilidade não mudou.

### Alterações nesta versão

- Manutenção do repositório: mantém notas de desenvolvimento local fora do código-fonte rastreado e dos pacotes de lançamento. O comportamento de jogabilidade não mudou.

## 5.8.3

Anuncia a versão instalada, clientes compatíveis e comando de configurações uma vez por login ou recarregamento da interface. Inclui links de feedback específicos do addon no CurseForge e GitHub; clicar em um link abre uma janela de cópia em estilo nativo. O comportamento de mensagens e a IU de cópia segura são compartilhados por meio da libchev privada 1.2.0. Se o registro de links ou a janela de cópia estiver indisponível, mostra a URL completa no chat. Um ajudante de boas-vindas indisponível não pode interromper a inicialização normal do addon.

### Alterações nesta versão

- Validação: 334 testes passam nas duas ordens no Lua 5.1 e 5.2, com verificações de API de cliente, análise Lua e verificação exata do fornecedor da biblioteca. Simulações de fumaça do NoPoizen exercitam ambos os links de feedback em todos os sete perfis de cliente/conjunto de regras. A renderização ao vivo permanece uma verificação separada.

## 5.8.2

Isola buscas de GUID da fixture de teste de jogadores próximos. Corrige duas falhas falsas em /qt test quando uma unidade real ocupa o token de placa de identificação usado pelas verificações de dica e ícone em cache. O comportamento das placas de identificação em jogo não mudou.

### Alterações nesta versão

- O ambiente offline agora inclui essa colisão de token e reproduz ambas as falhas sem a correção da fixture. Todos os 333 testes passam nas duas ordens no Lua 5.1 e 5.2 após a correção; seis perfis de API de cliente também passam. A confirmação em jogo permanece separada.

## 5.8.1

Mostra o marcador de missão da Blizzard ao lado de QuestTogether na lista de AddOns em vez do ponto de interrogação padrão.

### Alterações nesta versão

- Mostra o marcador de missão da Blizzard ao lado de QuestTogether na lista de AddOns em vez do ponto de interrogação padrão.

## 5.8.0

Compatibiliza clientes Classic atuais com payloads corretos de aceitação de missão, fallbacks protegidos de API de objetivos, possibilidade de compartilhamento desconhecida informada com honestidade, metadados de variante e verificações de regressão de API em seis clientes. Preserva o comportamento do Retail/Forever e utilitários de depuração compartilhados.

### Alterações nesta versão

- Validação: 333 testes passam nas duas ordens no Lua 5.1 e 5.2, com seis perfis de cliente, análise Lua e verificações exatas de fornecedor de biblioteca privada. Verificações de fumaça de cliente NoPoizen e verificação de pacote também passam. A validação ao vivo dos novos adaptadores continua pendente.
- Veja CLIENT_COMPATIBILITY.md para evidências de origem, escopo e limites de validação.

## 5.7.7

Mantém consoles de depuração sobrepostos e seus controles em um único grupo nativo de empilhamento por meio da libchev privada 1.1.3. Menus de categoria permanecem com seu console proprietário.

### Alterações nesta versão

- Por padrão, coloca ícones de objetivo de missão à esquerda da placa de identificação. Posições de ícones já salvas permanecem inalteradas.
- Respeita a configuração “My Last Name” do Forever ao exibir o nome do seu personagem. Mantém visíveis os sobrenomes de outros jogadores, correspondendo ao escopo da configuração nativa. Usa nomes completos de forma consistente para comunicações, membros do grupo, correspondência de placas de identificação e ações sociais, preservando as chaves existentes de perfil e de posição de balões pessoais.
- Corrige anúncios duplicados de missões locais causados por receber sua própria mensagem de canal em um formato diferente de nome completo. A cobertura de regressão exercita o anúncio local seguido por seus ecos de canal e grupo, incluindo outro personagem com o mesmo primeiro nome.
- Validação: 331 testes passam nas duas ordens no Lua 5.1/5.2. A confirmação ao vivo do novo padrão de ícone e da interação entre múltiplas janelas permanece separada.

## 5.7.6

Usa o mesmo console de depuração privado libchev 1.1.2 nos três addons, incluindo filtros de categoria/busca, controles de cópia, resultados de teste, relatórios de diagnóstico, registros de data/hora quando disponíveis e um único resumo final de teste. Corrige a arte esticada dos quadros nativos com limites de textura explícitos.

### Alterações nesta versão

- QuestTogether fornece seus próprios diagnósticos de missões e testes isolados, enquanto a biblioteca compartilhada controla o console e o comportamento genérico de depuração. Execute /qt test, /qt debug ou /qt diagnostics.
- Validação: 324 testes passam nas duas ordens no Lua 5.1/5.2. O usuário confirmou a aparência corrigida do quadro dentro do jogo. Outras validações de restrições ao vivo e de jogabilidade permanecem separadas.

## 5.7.6-beta.3

QuestTogether 5.7.6-beta.3 atualiza o console de depuração compartilhado incorporado para libchev 1.1.1.

### Alterações nesta versão

- Restaura a aparência de janela nativa no estilo do WoW no console compartilhado dos addons.
- Remove a linha duplicada de resumo de teste, mantendo o resumo final no histórico limitado.
- Mantém o comportamento comum de busca, categoria, cópia, rolagem, teste e diagnóstico, além das proteções de restrição existentes.
- O usuário relatou que todos os 324 testes do QT passaram no Forever 1.60.1 build 70009 na beta.2. Os sete arquivos de teste carregados ao vivo do QT também foram auditados quanto a aritmética inválida; nenhum fixture de geração de NaN ou divisão por zero foi encontrado. Esse resultado anterior de teste ao vivo não valida esta nova alteração de aparência.
- Depois de /reload, abra /qtd, execute /qt test e verifique a aparência da janela e o resumo único. A renderização ao vivo e o comportamento de restrição/taint desta revisão ainda precisam de verificação no cliente.
- Validação: todos os 324 casos passam em ordem normal/inversa no Lua 5.1.5 e 5.2.4 reais, cada execução CLI emite um resumo, e o ZIP instalável extraído com 26 arquivos passa nas duas versões. Todos os 23 arquivos Lua são analisados; todas as 22 entradas TOC e o manifesto do fornecedor são verificados. As verificações de formatação e diff passam. Pin da biblioteca: 2feea04bab60ba1c1b91bd01ab8a58ce02e091a9. Nenhum CI do GitHub do QT está configurado; o CI da biblioteca upstream passou.

## 5.7.6-beta.2

QuestTogether 5.7.6-beta.2 substitui sua janela de depuração separada pelo console compartilhado libchev v1.1 usado entre os addons. A biblioteca incorporada está incluída; nenhuma instalação separada é necessária.

### Alterações nesta versão

- Filtragem compartilhada por categoria, busca aproximada/com aspas, copiar/selecionar, limpar, recarregar, testes, diagnósticos e comportamento de acompanhar a rolagem.
- /qt test abre os resultados atuais; execuções repetidas substituem o histórico TEST antigo e limpam filtros de busca obsoletos.
- /qt diagnostics [questID] e /qt diag [questID] recriam o relatório atual em cache no mesmo console, mantendo eventos recentes dentro do orçamento de exportação compartilhado.
- Proteções compartilhadas de restrição e de quadro proprietário substituem os callbacks antigos do console do QT e a implementação de menu suspenso.
- Estado de missões, anúncios, placas de identificação, comunicações e isolamento de testes específicos do QT continuam sob responsabilidade do QuestTogether.
- Esta é uma versão beta. A renderização ao vivo no Retail/Forever e o comportamento de taint ainda precisam de verificação. Depois de /reload, execute /qt test e /qt diagnostics, então teste categoria/busca, copiar, limpar, redimensionar, rolagem, execuções repetidas de teste e alternância entre relatórios e logs. Inclua transições de combate/restrição e seu conjunto usual de addons.
- Validação: 324/324 testes passam nas duas ordens no Lua 5.1.5 e 5.2.4. Todos os 23 arquivos Lua são analisados, todas as 22 entradas TOC são validadas e o manifesto da biblioteca fixada é verificado. O ZIP instalável foi extraído e passou em todos os 324 casos usando o harness offline separado. Pin da biblioteca: 1f2cd0eaabb692fd0befd51dbdadeb7e07beb3c6.

## 5.7.6-beta.1

QuestTogether 5.7.6-beta.1 incorpora libchev v1.0.0 para compartilhar logs, diagnósticos, proteções de callback, mecânicas de trabalho adiado e execução de testes com os outros addons Together. A biblioteca está incluída; nenhuma instalação separada de addon é necessária.

### Alterações nesta versão

- Relatórios de diagnóstico incluem informações comuns de cliente/addon/biblioteca e mantêm os eventos mais recentes quando a janela de cópia fica cheia.
- O comportamento de missões, grupo, placas de identificação e restrições continua sob responsabilidade do QuestTogether, com armazenamentos de execução isolados por addon.
- Links de coordenadas permanecem utilizáveis enquanto o QT está desativado quando as restrições permitem; trabalhos em segundo plano na fila permanecem pausados e temporizadores obsoletos são descartados.
- /qt test agora inclui 315 casos: os 300 existentes, dez verificações da biblioteca compartilhada e cinco regressões de integração.
- Validação: todos os 315 testes passam nas duas ordens no Lua 5.1.5 e 5.2.4; a sintaxe Lua, a ordem de carregamento do TOC e o manifesto de revisão/hash incorporado passam. Fonte libchev incorporada: 09ac76eb6fe8e9589b809188652950c3cd9e444c.
- Esta é uma versão beta. A renderização da UI ao vivo no Retail/Forever e o comportamento de taint após esta extração ainda precisam de verificação. Depois de recarregar, execute /qt test e /qt diagnostics, então teste missões, bolhas de progresso, placas de identificação e links de coordenadas em combate, mudança de zona, desativação/reativação e recarregamento com seus addons usuais. A confirmação anterior de 300 testes no Retail se aplicava à v5.7.5.
