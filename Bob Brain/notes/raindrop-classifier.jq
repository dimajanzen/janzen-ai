[ .raindrops[] | select(.collection["$id"]==-1) ]
| map(
  . as $it
  | ((($it.title//"")+" "+($it.excerpt//"")+" "+($it.domain//"")+" "+(($it.tags//[])|join(" "))) | ascii_downcase) as $t
  | (
      if   ($t|test("pim|produktdaten|product data|magento|shopware|shopify|bmecat|ergonode|ainavio|katalog|catalog|pxm|produktbeschreib")) then {c:73999247,tg:["pim","ecommerce"]}
      elif ($t|test("akka|dotnet|\\.net|asp\\.net|blazor|nuget|entity framework|aspire| c#")) then {c:73999250,tg:(["dotnet"]+(if ($t|test("akka")) then ["akka"] else [] end))}
      elif ($t|test("cold call|cold-call|kaltakquise|outbound|sales navigator|\\bcrm\\b|lead gen|leadgen|\\bicp\\b|prospecting|revops|\\bsdr\\b|cold email|discovery call|vertrieb|kaltanruf")) then {c:73999249,tg:["sales"]}
      elif ($t|test("\\bseo\\b|\\bgtm\\b|go-to-market|content marketing|newsletter|landing page|landingpage|\\bgeo\\b|llms\\.txt|\\bfunnel\\b|positioning|demand gen|\\bmarketing\\b|personal brand|ghostwrit|copywrit")) then {c:73999248,tg:(["marketing"]+(if($t|test("seo|llms\\.txt|\\bgeo\\b"))then["seo"]else[]end)+(if($t|test("gtm|go-to-market"))then["gtm"]else[]end))}
      elif ($t|test("dividend|\\baktie|\\betf\\b|trading|\\bsteuer|finanzen|verm\u00f6gen|\\bfitness|muskel|ern\u00e4hrung|gesundheit|abnehmen|schlaf")) then {c:73999244,tg:(if($t|test("aktie|dividend|etf|trading|steuer|finanz|verm\u00f6gen"))then["aktien","finance"]else["health"]end)}
      elif ($t|test("startup|founder|first customer|bootstrap|indie ?hacker|\\bmvp\\b|product[- ]market fit|\\bpmf\\b|gr\u00fcnd|solopreneur|micro saas|buildinpublic")) then {c:73999242,tg:["startup"]}
      elif ($t|test("f\u00fchrung|leadership|mindset|produktiv|gewohnheit|\\bhabit|coaching|delegation|hiring|\\bproverb|sprichwort|motivation|disziplin|product management|entscheidung|\\bteam\\b|\\bmeeting|\\bokr")) then {c:73999252,tg:["leadership"]}
      elif ($t|test("\\bbook\\b|\\bbuch\\b|reading list|leseliste|buchtipp|\\bpodcast")) then {c:73999253,tg:["books"]}
      elif ($t|test("\\bai\\b|\\bki\\b|\\bllm|agent|claude|\\bgpt|chatgpt|prompt|\\brag\\b|\\bmcp\\b|n8n|coding|\\bcode\\b|developer|github|docker|react|python|typescript|harness|openai|anthropic|gemini|grok|mistral|cursor|copilot|\\bapi\\b|framework|kubernetes|\\bmodel|\\bhugging")) then {c:73999251,tg:(["ai"]+(if($t|test("agent"))then["agents"]else[]end)+(if($t|test("code|coding|developer|github|docker|react|python|typescript|framework|kubernetes|deploy"))then["dev"]else[]end))}
      else {c:0,tg:[]} end
    ) as $r
  | {id:$it._id, c:$r.c, tags:($r.tg|unique|.[0:3])}
)
