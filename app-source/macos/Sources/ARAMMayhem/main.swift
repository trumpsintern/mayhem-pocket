import SwiftUI
import AppKit

struct Champion: Identifiable, Hashable { let id, key, name, slug: String; let icon: URL }
struct Item: Identifiable, Hashable { let id, name: String; let tier, price: Int; let tags: [String]; let icon: URL; var grade: String { ["S","S","A","B","C","D"][min(max(tier,0),5)] } }
struct Augment: Identifiable, Hashable { let id, name, detail: String; let tier, rarity: Int; let icon: URL?; var grade: String { ["S","A","B","C","D","F"][min(max(tier,0),5)] } }
struct StartSet: Identifiable { let id: String; let items: [Item] }
struct NamedIcon: Identifiable { let id=UUID(); let name:String; let url:URL }
struct Build { let patch, date: String; let starts, coreSets: [StartSet]; let boots: [Item]; let spellSets:[[NamedIcon]]; let skillPriority, skillOrder:[String]; let augments: [Augment] }

actor Service {
    static let shared = Service(); let session = URLSession(configuration: .default)
    var patch = "", itemRecords: [String:ItemJSON] = [:], augmentRecords: [String:AugJSON] = [:]
    func get<T: Decodable>(_ type: T.Type, _ string: String, force: Bool = false) async throws -> T {
        var req = URLRequest(url: URL(string:string)!); req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X)", forHTTPHeaderField:"User-Agent"); if force { req.cachePolicy = .reloadIgnoringLocalCacheData }
        let (data,res) = try await session.data(for:req); guard let h=res as? HTTPURLResponse, (200...299).contains(h.statusCode) else { throw URLError(.badServerResponse) }; return try JSONDecoder().decode(T.self,from:data)
    }
    func champions(force: Bool=false) async throws -> [Champion] {
        let versions:[String] = try await get([String].self,"https://ddragon.leagueoflegends.com/api/versions.json",force:force); patch=versions[0]
        let root:ChampRoot = try await get(ChampRoot.self,"https://ddragon.leagueoflegends.com/cdn/\(patch)/data/en_US/champion.json",force:force)
        return root.data.values.map { c in Champion(id:c.id,key:c.key,name:c.name,slug:Self.slug(c.id),icon:URL(string:"https://ddragon.leagueoflegends.com/cdn/\(patch)/img/champion/\(c.image.full)")!) }.sorted{$0.name<$1.name}
    }
    func build(_ champ: Champion, force: Bool=false) async throws -> Build {
        if patch.isEmpty { _ = try await champions(force:force) }
        async let itemsTask:ItemRoot = get(ItemRoot.self,"https://ddragon.leagueoflegends.com/cdn/\(patch)/data/en_US/item.json",force:force)
        let items=try await itemsTask; itemRecords=items.data
        var map:[String:Item]=[:]
        for (id,x) in items.data where x.gold.purchasable { map[id]=Item(id:id,name:x.name,tier:0,price:x.gold.total,tags:x.tags,icon:URL(string:"https://ddragon.leagueoflegends.com/cdn/\(patch)/img/item/\(x.image.full)")!) }
        let opgg=try await opggBuild(champ.slug,map:map,force:force)
        guard !opgg.starts.isEmpty, !opgg.cores.isEmpty, !opgg.augments.isEmpty else { throw URLError(.cannotParseResponse) }
        return Build(patch:patch,date:Date().formatted(date:.abbreviated,time:.shortened),starts:opgg.starts,coreSets:opgg.cores,boots:opgg.boots,spellSets:opgg.spellSets,skillPriority:opgg.priority,skillOrder:opgg.order,augments:opgg.augments)
    }
    func opggBuild(_ slug:String,map:[String:Item],force:Bool) async throws -> (starts:[StartSet],cores:[StartSet],boots:[Item],spellSets:[[NamedIcon]],priority:[String],order:[String],augments:[Augment]) {
        var req=URLRequest(url:URL(string:"https://op.gg/lol/modes/aram-mayhem/\(slug)/build")!); req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X)",forHTTPHeaderField:"User-Agent"); if force {req.cachePolicy = .reloadIgnoringLocalCacheData}
        async let buildData=session.data(for:req)
        var augReq=URLRequest(url:URL(string:"https://op.gg/lol/modes/aram-mayhem/\(slug)/augments")!);augReq.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X)",forHTTPHeaderField:"User-Agent");if force{augReq.cachePolicy = .reloadIgnoringLocalCacheData}
        async let augmentData=session.data(for:augReq)
        let(data,_)=try await buildData;let(aData,_)=try await augmentData;guard let raw=String(data:data,encoding:.utf8),let augRaw=String(data:aData,encoding:.utf8) else{return([],[],[],[],[],[],[])};let html=raw.replacingOccurrences(of:"\\\"",with:"\"") as NSString
        let ids=try NSRegularExpression(pattern:"\"metaId\":([0-9]+)")
        func rows(_ prefix:String, limit:Int, boundary:String?=nil)->[StartSet]{let ms=(try? NSRegularExpression(pattern:"\"\(prefix)_[0-9]+\"").matches(in:html as String,range:NSRange(location:0,length:html.length))) ?? [];return ms.prefix(limit).enumerated().compactMap{i,m in let start=NSMaxRange(m.range);var stop=i+1<ms.count ? ms[i+1].range.location:min(start+16000,html.length);if let boundary{let b=html.range(of:"\"\(boundary)_0\"",options:[],range:NSRange(location:start,length:max(0,stop-start)));if b.location != NSNotFound{stop=b.location}};var seen=Set<String>();let found=ids.matches(in:html as String,range:NSRange(location:start,length:max(0,stop-start))).compactMap{r->Item? in let id=html.substring(with:r.range(at:1));guard seen.insert(id).inserted else{return nil};return map[id]};return found.isEmpty ? nil:StartSet(id:"\(prefix)\(i)",items:found)}}
        let starts=rows("starter_items",limit:3,boundary:"boots"), cores=rows("core_items",limit:5), bootRows=rows("boots",limit:3,boundary:"core_items"), boots=bootRows.compactMap{$0.items.first}
        let string=html as String; let skillTable=string.range(of:"SkillOrder Table",options:.backwards)?.lowerBound
        let spellMarker=try NSRegularExpression(pattern:"\"spell_0\"");let sms=spellMarker.matches(in:string,range:NSRange(string.startIndex..<string.endIndex,in:string));var spellSets:[[NamedIcon]]=[];let spellRE=try NSRegularExpression(pattern:"src\":\"(https:[^\"]+/spell/[^\"]+)\"[^}]+alt\":\"([^\"]+)\"")
        for (i,m) in sms.enumerated(){let start=NSMaxRange(m.range),stop=i+1<sms.count ? sms[i+1].range.location:min(start+3500,(string as NSString).length);let section=(string as NSString).substring(with:NSRange(location:start,length:max(0,stop-start)));var pair:[NamedIcon]=[];for x in spellRE.matches(in:section,range:NSRange(section.startIndex..<section.endIndex,in:section)).prefix(2){if let ur=Range(x.range(at:1),in:section),let nr=Range(x.range(at:2),in:section),let u=URL(string:String(section[ur])){pair.append(NamedIcon(name:String(section[nr]),url:u))}};if pair.count==2 && !spellSets.contains(where:{$0.map(\.name)==pair.map(\.name)}){spellSets.append(pair)}}
        var priority:[String]=[], order:[String]=[]
        if let a=skillTable {let section=String(string[a...].prefix(14000));let p=try NSRegularExpression(pattern:"extraData\":\"([QWE])\"");priority=p.matches(in:section,range:NSRange(section.startIndex..<section.endIndex,in:section)).prefix(3).compactMap{Range($0.range(at:1),in:section).map{String(section[$0])}};if let levelStart=section.range(of:"inline-flex flex-wrap gap-0.5"){let levels=String(section[levelStart.lowerBound...]);let r=try NSRegularExpression(pattern:"children\":\"([QWER])\"");order=r.matches(in:levels,range:NSRange(levels.startIndex..<levels.endIndex,in:levels)).prefix(15).compactMap{Range($0.range(at:1),in:levels).map{String(levels[$0])}}}}
        let cleanAug=augRaw.replacingOccurrences(of:"\\\"",with:"\"");let augRE=try NSRegularExpression(pattern:"\\{\"id\":([0-9]+),\"tier\":([0-9]+),\"performance\":[^,]+,\"popular\":[^,]+,\"name\":\"([^\"]+)\",\"key\":\"[^\"]+\",\"largeIcon\":\"([^\"]+)\",\"smallIcon\":\"[^\"]+\",\"rarity\":([0-9]+),\"desc\":\"(.*?)\",\"tooltip\"")
        let augNS=cleanAug as NSString;var augments:[Augment]=[];var seenAug=Set<String>();for x in augRE.matches(in:cleanAug,range:NSRange(location:0,length:augNS.length)){let id=augNS.substring(with:x.range(at:1));guard seenAug.insert(id).inserted else{continue};let tier=Int(augNS.substring(with:x.range(at:2))) ?? 0;let name=augNS.substring(with:x.range(at:3)).jsonDecoded;let icon=URL(string:augNS.substring(with:x.range(at:4))+"?image=q_auto:good,f_png,w_96,h_96");let rawR=Int(augNS.substring(with:x.range(at:5))) ?? 1;let rarity=rawR==8 ? 2:rawR==4 ? 1:0;let desc=augNS.substring(with:x.range(at:6)).jsonDecoded.clean;augments.append(Augment(id:id,name:name,detail:desc,tier:tier,rarity:rarity,icon:icon))}
        return(starts,cores,boots,spellSets,priority,order,augments)
    }
    static func slug(_ id:String)->String { ["MonkeyKing":"wukong","KSante":"ksante","Kaisa":"kaisa","Khazix":"khazix","Velkoz":"velkoz","RekSai":"reksai","Belveth":"belveth","Chogath":"chogath"][id] ?? id.lowercased() }
}

@MainActor final class Model: ObservableObject {
    @Published var champions:[Champion]=[]
    @Published var selected:Champion?
    @Published var query=""
    @Published var loading=true
    @Published var error=""
    @Published var build:Build?
    @Published var pinned=false {didSet{NSApp.windows.first?.level=pinned ? .floating:.normal}}
    var matches:[Champion]{query.isEmpty ? champions:champions.filter{$0.name.localizedCaseInsensitiveContains(query)}}
    func start() async { do{champions=try await Service.shared.champions(); select(champions.first{$0.name=="Aatrox"} ?? champions.first)}catch{self.error=error.localizedDescription;loading=false} }
    func select(_ c:Champion?){guard let c else{return};selected=c;query=c.name;Task{await refresh()}}
    func refresh(force:Bool=false) async {guard let c=selected else{return};loading=true;error="";do{build=try await Service.shared.build(c,force:force)}catch{self.error=error.localizedDescription};loading=false}
    func opgg(){guard let c=selected else{return};NSWorkspace.shared.open(URL(string:"https://op.gg/lol/modes/aram-mayhem/\(c.slug)/build")!)} }

struct ContentView:View { @EnvironmentObject var m:Model; @State var show=false; @State var rarity=2
    var body:some View{VStack(spacing:0){header;Divider();if m.loading{Spacer();ProgressView("Loading current OP.GG recommendations…");Spacer()}else if !m.error.isEmpty{Spacer();VStack(spacing:12){Image(systemName:"wifi.exclamationmark").font(.largeTitle);Text("Couldn’t read OP.GG data").font(.headline);Text(m.error).foregroundStyle(.secondary);Button("Try Again"){Task{await m.refresh(force:true)}}};Spacer()}else if let b=m.build{ScrollView{VStack(alignment:.leading,spacing:22){HStack{Text("Patch \(b.patch)");Text("Fetched \(b.date)");Spacer();Text("Live OP.GG recommendations")}.font(.caption).foregroundStyle(.secondary);spells(b.spellSets);skills(b.skillPriority,b.skillOrder);starts(b.starts);items("Boots",b.boots);sequences(b.coreSets);augmentList(b.augments);Divider();Text("All displayed recommendations and rankings are read from OP.GG when this champion is loaded. Riot Data Dragon supplies current item and champion artwork. Unofficial and not affiliated with Riot Games or OP.GG.").font(.caption2).foregroundStyle(.secondary)}.padding(18)}}}.frame(minWidth:720,minHeight:620).task{await m.start()}}
    var header:some View{HStack(spacing:12){if let c=m.selected{AsyncImage(url:c.icon){$0.resizable()}placeholder:{Color.gray.opacity(0.2)}.frame(width:48,height:48).clipShape(RoundedRectangle(cornerRadius:10))};VStack(alignment:.leading){Text("MAYHEM POCKET").font(.caption.bold()).foregroundStyle(.cyan);ZStack(alignment:.topLeading){TextField("Type a champion…",text:$m.query).onTapGesture{show=true}.onChange(of:m.query){_ in show=true}.onSubmit{m.select(m.matches.first);show=false};if show && m.query != m.selected?.name{ScrollView{VStack(spacing:0){ForEach(m.matches.prefix(8)){c in Button(c.name){m.select(c);show=false}.buttonStyle(.plain).frame(maxWidth:.infinity,alignment:.leading).padding(6)}}}.frame(height:min(CGFloat(m.matches.prefix(8).count)*30,180)).background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius:7)).offset(y:25).zIndex(5)}}}.zIndex(5);Spacer();Toggle(isOn:$m.pinned){Image(systemName:"pin.fill")}.toggleStyle(.button);Button{Task{await m.refresh(force:true)}}label:{Image(systemName:"arrow.clockwise")};Button("Open OP.GG"){m.opgg()}}.padding(16).zIndex(10)}
    func items(_ title:String,_ values:[Item])->some View{VStack(alignment:.leading,spacing:9){Text(title).font(.headline);ScrollView(.horizontal,showsIndicators:false){HStack{ForEach(values){x in VStack(alignment:.leading){ZStack(alignment:.topTrailing){AsyncImage(url:x.icon){$0.resizable()}placeholder:{Color.gray.opacity(0.2)}.frame(width:54,height:54).clipShape(RoundedRectangle(cornerRadius:8));badge(x.grade)};Text(x.name).font(.caption.bold()).lineLimit(2).frame(width:92,alignment:.leading);Text("\(x.price)g").font(.caption2).foregroundStyle(.secondary)}.padding(9).background(.quaternary.opacity(0.45)).clipShape(RoundedRectangle(cornerRadius:11))}}}}}
    func starts(_ sets:[StartSet])->some View{VStack(alignment:.leading,spacing:9){HStack{Text("Starting sets").font(.headline);Text("OP.GG combinations").font(.caption2).foregroundStyle(.secondary)};ScrollView(.horizontal,showsIndicators:false){HStack{ForEach(Array(sets.enumerated()),id:\.element.id){i,set in VStack(alignment:.leading){Text(i==0 ? "MOST COMMON":"OPTION \(i+1)").font(.caption2.bold()).foregroundStyle(i==0 ? .cyan:.secondary);HStack{ForEach(set.items){x in VStack{AsyncImage(url:x.icon){$0.resizable()}placeholder:{Color.gray.opacity(0.2)}.frame(width:48,height:48).clipShape(RoundedRectangle(cornerRadius:8));Text(x.name).font(.caption2).lineLimit(1).frame(width:75)}}}}.padding(10).background(.quaternary.opacity(0.45)).clipShape(RoundedRectangle(cornerRadius:11))}}}}}
    @ViewBuilder func spells(_ sets:[[NamedIcon]])->some View {
        if !sets.isEmpty {
            VStack(alignment:.leading,spacing:9) {
                Text("Summoner spells").font(.headline)
                ForEach(Array(sets.enumerated()),id:\.offset) { _,values in HStack { ForEach(values) { x in VStack { AsyncImage(url:x.url){$0.resizable()}placeholder:{Color.gray.opacity(0.2)}.frame(width:48,height:48).clipShape(RoundedRectangle(cornerRadius:8)); Text(x.name).font(.caption2) } } } }
            }
        }
    }
    @ViewBuilder func skills(_ priority:[String],_ order:[String])->some View {
        if !priority.isEmpty || !order.isEmpty {
            VStack(alignment:.leading,spacing:9) {
                Text("Skills").font(.headline)
                if !priority.isEmpty { HStack { ForEach(Array(priority.enumerated()),id:\.offset) { i,s in
                    if i>0 { Image(systemName:"chevron.right").foregroundStyle(.secondary) }; skillBox(s)
                } } }
                if !order.isEmpty { HStack(spacing:4) { ForEach(Array(order.enumerated()),id:\.offset) { _,s in skillBox(s) } } }
            }
        }
    }
    func skillBox(_ value:String)->some View{Text(value).font(.subheadline.bold()).foregroundStyle(value=="R" ? .white:.cyan).frame(width:32,height:32).background(value=="R" ? Color.indigo:Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:6))}
    func sequences(_ sets:[StartSet])->some View {
        VStack(alignment:.leading,spacing:9) {
            Text("Build order").font(.headline)
            ForEach(Array(sets.enumerated()),id:\.element.id) { i,set in
                HStack { Text("\(i+1)").font(.caption.bold()).foregroundStyle(.secondary).frame(width:18)
                    ForEach(Array(set.items.enumerated()),id:\.element.id) { j,x in
                        if j>0 { Image(systemName:"chevron.right").foregroundStyle(.secondary) }
                        VStack { AsyncImage(url:x.icon){$0.resizable()}placeholder:{Color.gray.opacity(0.2)}.frame(width:50,height:50).clipShape(RoundedRectangle(cornerRadius:8)); Text(x.name).font(.caption2).lineLimit(1).frame(width:80) }
                    }
                }.padding(10).frame(maxWidth:.infinity,alignment:.leading).background(.quaternary.opacity(0.35)).clipShape(RoundedRectangle(cornerRadius:10))
            }
        }
    }
    func augmentList(_ all:[Augment])->some View{VStack(alignment:.leading,spacing:10){Text("Best augments").font(.headline);HStack(spacing:0){tab("Prismatic",2,.purple);tab("Gold",1,.yellow);tab("Silver",0,.gray)}.background(.quaternary.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius:10));LazyVStack{ForEach(all.filter{$0.rarity==rarity}){a in HStack(alignment:.top){Group{if let u=a.icon{AsyncImage(url:u){$0.resizable()}placeholder:{color.opacity(0.2)}}else{Image(systemName:"sparkles").resizable().scaledToFit().padding(9).foregroundStyle(color)}}.frame(width:46,height:46).clipShape(RoundedRectangle(cornerRadius:8));VStack(alignment:.leading){Text(a.name).font(.subheadline.bold());Text(a.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)};Spacer();badge(a.grade)}.padding(10).background(.quaternary.opacity(0.35)).clipShape(RoundedRectangle(cornerRadius:10))}}}}
    var color:Color{rarity==2 ? .purple:rarity==1 ? .yellow:.gray};func tab(_ name:String,_ value:Int,_ c:Color)->some View{Button{rarity=value}label:{ZStack{Rectangle().fill(rarity==value ? c.opacity(0.18):Color.clear);Text(name).font(.subheadline.bold()).foregroundStyle(c)}.frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())}.buttonStyle(.plain).contentShape(Rectangle())};func badge(_ s:String)->some View{Text(s).font(.caption2.bold()).padding(.horizontal,6).padding(.vertical,3).background(s=="S" ? Color.pink:Color.indigo).foregroundStyle(.white).clipShape(Capsule())}}

@main struct MayhemApp:App{@StateObject var model=Model();var body:some Scene{WindowGroup("Mayhem Pocket"){ContentView().environmentObject(model)}.defaultSize(width:780,height:680)}}

extension String { var jsonDecoded:String { (try? JSONDecoder().decode(String.self,from:Data(("\""+self+"\"").utf8))) ?? self }; var clean:String { replacingOccurrences(of:"<[^>]+>",with:"",options:.regularExpression).replacingOccurrences(of:"@[^@]+@",with:"",options:.regularExpression).replacingOccurrences(of:"&amp;",with:"&").replacingOccurrences(of:"&#39;",with:"'") } }
struct ChampRoot:Decodable{let data:[String:ChampJSON]};struct ChampJSON:Decodable{let id,key,name:String;let image:ImageJSON};struct ImageJSON:Decodable{let full:String}
struct RankRoot:Decodable{let data:[RankRow]};struct RankRow:Decodable{let dt,patch:String?;let data:RankData};struct RankData:Decodable{let items,augments:[String:TierJSON]};struct TierJSON:Decodable{let tier:Int}
struct ItemRoot:Decodable{let data:[String:ItemJSON]};struct ItemJSON:Decodable{let name:String;let image:ImageJSON;let gold:GoldJSON;let tags:[String]};struct GoldJSON:Decodable{let purchasable:Bool;let total:Int}
struct AugJSON:Decodable{let displayName,description:String;let enabled:Bool?;let iconLarge:String?;let rarity:Int}
