# Incidente 0004 — incompatibilidade Pest/PHPStan na feature de campo

## Sintoma

O `bin/check` do primeiro retry reprovou no PHPStan, embora a suíte Pest
estivesse verde. O analisador inferiu `Pest\\PendingCalls\\TestCall` para uma
chamada `$this->artisan()` e apontou `method.notFound`.

## Causa raiz

O teste misturava a API do objeto de teste com a forma de console que o
PHPStan consegue inferir no contexto instalado do projeto. A falha era de
tipagem estática do teste, não do comando Artisan em runtime.

## Correção

O systematic debugging registrou a hipótese, consultou a documentação atual
do plugin Laravel para Pest via Context7 e anexou a orientação ao retry. A
sessão seguinte substituiu a chamada problemática por `Artisan::call()` com
asserções booleanas explícitas e manteve `JSON_THROW_ON_ERROR` para a saída.

## Prevenção

Features de console devem executar o portão completo `bin/check`, não somente
Pest. Quando uma API fluente gerar inferência ambígua, o teste deve preferir
uma chamada explícita cujo tipo seja reconhecido pelo PHPStan 8 do projeto.

## Evidência

No workflow final `wf_field_refactor_radar_20260808_004`, o gate quality
registrou PHPStan sem erros, Pest com 501/501 testes, fronteiras com 7/7
testes, Pint, build de assets e tema CSS verdes.

## Risco residual

A forma de teste deve ser revalidada quando a versão do Pest, do plugin
Laravel ou do PHPStan mudar. A documentação oficial da versão instalada
continua superior a esta lição histórica.
