# THOTH Multi-AI External Dialogue — Proof 008

**UTC:** 2026-10-02T07:52:18.795890+00:00
**Transport:** GitHub Actions hosted runner → anonymous dynamic LLM router
**THOTH WEB dependency:** NO
**VPS dependency:** NO
**THOTH code touched:** NO

## IA-A
- Router selector: `default`
- Actual response model: `codestral-latest`
- HTTP 200 · 2.025 s

ACK THOTH-EXT-A-08. A arquitetura mínima viável consiste em:

1. **Banco de Dados Externo**: PostgreSQL com schema para proveniência (timestamp, origem, estado) e tarefas (ID, status, payload).
2. **Fila de Tarefas**: Redis Streams para enfileirar tarefas com TTL e deduplicação via UUID.
3. **API de Controle**: Serviço leve (FastAPI) para gerenciar estados, auditando todas as operações via logs estruturados.
4. **THOTH WEB**: Apenas frontend para visualização (read-only), sem lógica de negócio.

**Falha crítica a testar primeiro**: Condição de corrida na atualização de estados. Simule duas IAs tentando modificar o mesmo estado simultaneamente e verifique se o PostgreSQL bloqueia corretamente ou se há inconsistências.

## IA-B
- Router selector: `mistral-Nemo-Instruct-2407`
- Actual response model: `mistral-Nemo-Instruct-2407`
- HTTP 200 · 15.272 s

ACK THOTH-EXT-B-08. Mantendo a arquitetura minimalista, a solução proposta pela IA-A é robusta e escalável. A utilização do Redis Streams para a fila de tarefas é uma boa escolha devido à sua capacidade de processamento em tempo real e sua funcionalidade de TTL e deduplicação via UUID.

No entanto, eu mudaria a abordagem do banco de dados externo. Em vez de utilizar o PostgreSQL, eu sugeriria o uso do CockroachDB, que é um banco de dados distribuído e tolerante a falhas, projetado para lidar com grandes volumes de dados e transações complexas. Isso proporcionaria uma maior disponibilidade e consistência dos dados, especialmente em situações de alta carga.

Para testar a retomada após a queda do coordenador sem duplicar tarefas, eu proporia o seguinte teste falsificável: após a queda do coordenador, simular a adição de novas tarefas à fila. Em seguida, verificar se o sistema é capaz de processar essas tarefas sem duplicá-las após a retomada do coordenador. Isso pode ser feito monitorando o número de tarefas na fila antes e depois da queda do coordenador, bem como verificando se as tarefas processadas correspondem às tarefas adicionadas à fila.


## Falsifiable checks
- B received A verbatim: **True**
- A/B actual response models distinct: **True**
- C received A+B verbatim: **False**
- Three actual models distinct: **False**
- A ACK: **True**
- B ACK: **True**
- C ACK: **False**
- Minimum external dialogue proven: **True**
