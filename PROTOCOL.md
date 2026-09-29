# THOTH Browser Bridge Protocol v1

A ponte usa tarefas criptografadas. O repositorio nunca deve receber cookies, senhas, tokens, OTP, dados de pagamento ou resultados em texto puro.

Fluxo:
1. ChatGPT le a chave publica da VPS.
2. Gera uma chave efemera por tarefa.
3. Criptografa o comando.
4. Grava apenas o envelope cifrado em queue.json.
5. A VPS executa a tarefa no THOTH Browser.
6. A resposta volta cifrada e expira automaticamente.

Acoes sensiveis continuam exigindo intervencao humana pela tela remota.
