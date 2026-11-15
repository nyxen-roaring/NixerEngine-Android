package states.editors;

import backend.StageData;
import backend.Song;
import backend.MenuBG;

import objects.Character;

import flixel.FlxObject;
import flixel.FlxBasic;
import flixel.math.FlxPoint;
import flixel.util.FlxSpriteUtil;
import flixel.group.FlxGroup;
import haxe.Json;
import openfl.utils.AssetType;
import mobile.backend.MobileScaleMode;
import mobile.backend.MobileData;

typedef CamEvent = {
	var group:Array<Dynamic>; // [tiempo, [[nombre, valor1, valor2], ...]]
	var sub:Array<Dynamic>;   // [nombre, valor1, valor2]
}

/**
 * Editor de cámara NixerEngine (usa el stage de la canción que se juega o se charta: PlayState.SONG.stage).
 *
 * Modo STAGE:  edita camera_boyfriend, camera_opponent, camera_girlfriend, defaultZoom y camera_speed
 *              del JSON del stage y los guarda en él.
 * Modo EVENTS: edita los eventos de cámara de la canción (Camera Follow Pos, Add Camera Zoom, Screen Shake).
 *
 * La vista previa dibuja los objetos del stage (los que están en el JSON), los personajes reales,
 * los puntos de cámara de BF / oponente / GF y el recuadro de lo que ve la cámara del juego.
 *
 * Controles (botones en pantalla de Android):
 *   ARRIBA / ABAJO ... elegir fila      IZQUIERDA / DERECHA ... cambiar el valor (Y = x10)
 *   A ... ejecutar la fila (Guardar, Añadir, Borrar...)      B ... volver (dos veces si hay cambios sin guardar)
 *   Vista previa: arrastra con un dedo para mover, pellizca con dos dedos para el zoom.
 */
class CameraEditorState extends MusicBeatState
{
	static inline final DESIGN_H:Float = 720;
	static inline final CARD_W:Float = 340;
	static inline final CARD_Y:Float = 92;
	static inline final ROW_H:Float = 46;
	static inline final LIST_TOP:Float = 150;
	static inline final LIST_BOTTOM:Float = 690;
	static inline final ACCENT:Int = 0xFF00F0FF;
	static inline final ACCENT2:Int = 0xFFB000FF;

	static final CAM_NAMES:Array<String> = ['Camera Follow Pos', 'Add Camera Zoom', 'Screen Shake'];

	var returnToChart:Bool = false;

	public function new(?returnToChart:Bool = false)
	{
		this.returnToChart = returnToChart;
		super();
	}

	var W:Float = 1280;
	var H:Float = 720;
	var s:Float = 1;
	var fontPath:String;

	// ---- cámaras
	var camWorld:FlxCamera;
	var camUI:FlxCamera;

	// ---- datos
	var song:SwagSong;
	var stageName:String = 'stage';
	var stageFile:StageFile;
	var stageDirty:Bool = false;
	var evSelected:Int = 0;
	var camEvents:Array<CamEvent> = [];
	var leavePending:Bool = false;

	// ---- mundo (vista previa)
	var worldGroup:FlxTypedGroup<FlxSprite> = new FlxTypedGroup<FlxSprite>();
	var overlayGroup:FlxGroup = new FlxGroup();
	var bfChar:Character = null;
	var dadChar:Character = null;
	var gfChar:Character = null;
	var bfSpr:FlxSprite;
	var dadSpr:FlxSprite;
	var gfSpr:FlxSprite;
	var markers:Array<FlxSprite> = [];
	var markerLabels:Array<FlxText> = [];
	var eventMarker:FlxSprite;
	var vp:Array<FlxSprite> = [];
	var previewZoom:Float = 0.4;
	var viewTarget:Int = 0; // 0 BF, 1 oponente, 2 GF
	var focusX:Float = 0;
	var focusY:Float = 0;
	var panX:Float = 0;
	var panY:Float = 0;
	var pinchLast:Float = -1;
	var dragging:Bool = false;
	var dragLastX:Float = 0;
	var dragLastY:Float = 0;

	// ---- interfaz
	var mode:Int = 0; // 0 = STAGE, 1 = EVENTS
	var rowIds:Array<String> = [];
	var rowLabels:Array<FlxText> = [];
	var rowValues:Array<FlxText> = [];
	var curRow:Int = 0;
	var scroll:Float = 0;
	var rowBar:FlxSprite;
	var rowBarY:Float = 0;
	var card:FlxSprite;
	var cardLeft:FlxSprite;
	var cardTop:FlxSprite;
	var cardTitle:FlxText;
	var cardSub:FlxText;
	var cardSep:FlxSprite;
	var cardX:Float = 0;
	var cardWpx:Float = 340;
	var titleText:FlxText;
	var infoText:FlxText;
	var hintText:FlxText;
	var msgText:FlxText;
	var rightPanel:FlxSprite;
	var introProg:Float = 0;
	var animT:Float = 0;
	var holdTime:Float = 0;
	var msgTimer:Float = 0;

	function num(a:Array<Dynamic>, i:Int, def:Float):Float
	{
		if (a == null || a.length <= i || a[i] == null) return def;
		var f:Float = Std.parseFloat(Std.string(a[i]));
		return Math.isNaN(f) ? def : f;
	}

	function arr2(a:Array<Float>):Array<Float>
	{
		if (a == null) a = [0, 0];
		while (a.length < 2) a.push(0);
		return a;
	}

	function round(v:Float, d:Int):Float
	{
		var m:Float = Math.pow(10, d);
		return Math.round(v * m) / m;
	}

	// ------------------------------------------------------------------ crear
	override function create()
	{
		FlxG.camera.bgColor = 0xFF05060F;
		FlxG.mouse.visible = false;
		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Camera Editor", null);
		#end

		W = FlxG.width + MobileScaleMode.gameCutoutSize.x * 2;
		H = FlxG.height;
		s = H / DESIGN_H;
		fontPath = Paths.font('vcr.ttf');
		if (Paths.fileExists('fonts/freeplay.otf', AssetType.FONT)) fontPath = Paths.font('freeplay.otf');
		else if (Paths.fileExists('fonts/freeplay.ttf', AssetType.FONT)) fontPath = Paths.font('freeplay.ttf');

		camUI = new FlxCamera();
		camUI.bgColor.alpha = 0;

		song = PlayState.SONG;
		if (song == null)
		{
			buildEmptyScreen();
			super.create();
			return;
		}

		// El stage es el de la canción que se juega o se charta
		stageName = song.stage;
		if (stageName == null || stageName.length < 1)
			stageName = StageData.vanillaSongStage(Paths.formatToSongPath(song.song));
		stageFile = StageData.getStageFile(stageName);
		fixStageFile();

		// Cámara del mundo (vista previa) a la izquierda; la interfaz va en otra cámara encima
		cardWpx = CARD_W * s;
		cardX = W - cardWpx - 10 * s;
		var camW:Int = Std.int(cardX - 14 * s);
		var camH:Int = Std.int(H - 70 * s - 56 * s);
		camWorld = new FlxCamera(0, Std.int(70 * s), camW, camH);
		camWorld.bgColor = 0xFF0A0E22;
		camWorld.zoom = previewZoom;
		FlxG.cameras.add(camWorld, false);
		FlxG.cameras.add(camUI, false);

		var bg:FlxSprite = MenuBG.create('menuDesat');
		bg.color = 0xFF10163A;
		add(bg);

		buildWorld();
		buildUI();
		collectEvents();
		setMode(0);

		addPad();
		super.create();
	}

	function addPad():Void
	{
		var dpad:String = 'NONE';
		for (m in ['LEFT_FULL', 'FULL', 'UP_DOWN'])
		{
			if (MobileData.dpadModes.exists(m))
			{
				dpad = m;
				break;
			}
		}
		var action:String = 'A_B';
		for (m in ['A_B_X_Y'])
		{
			if (MobileData.actionModes.exists(m))
			{
				action = m;
				break;
			}
		}
		addTouchPad(dpad, action);
	}

	function buildEmptyScreen():Void
	{
		FlxG.cameras.add(camUI, false);
		var t:FlxText = new FlxText(40, 0, W - 80, 'No song loaded.\nOpen the Camera Editor from the Chart Editor, or play a song first.\n\nPress B to go back.', 28);
		t.setFormat(fontPath, 28, FlxColor.WHITE, CENTER);
		t.screenCenter(Y);
		t.cameras = [camUI];
		add(t);
		addPad();
	}

	// El JSON de algunos stages no trae todos los campos
	function fixStageFile():Void
	{
		stageFile.camera_boyfriend = arr2(stageFile.camera_boyfriend);
		stageFile.camera_opponent = arr2(stageFile.camera_opponent);
		stageFile.camera_girlfriend = arr2(stageFile.camera_girlfriend);
		if (stageFile.camera_speed == null) stageFile.camera_speed = 1;
		if (stageFile.boyfriend == null) stageFile.boyfriend = [770, 100];
		if (stageFile.girlfriend == null) stageFile.girlfriend = [400, 130];
		if (stageFile.opponent == null) stageFile.opponent = [100, 100];
	}

	// ------------------------------------------------------------------ mundo
	function tryChar(name:String, isPlayer:Bool):Character
	{
		if (name == null || name.length < 1) return null;
		try
		{
			return new Character(0, 0, name, isPlayer);
		}
		catch (e:Dynamic)
		{
			trace('No se pudo cargar el personaje ' + name + ': ' + e);
			return null;
		}
	}

	function placeChar(ch:Character, x:Float, y:Float):Void
	{
		ch.setPosition(x + ch.positionArray[0], y + ch.positionArray[1]);
	}

	function buildWorld():Void
	{
		var bfX:Float = num(stageFile.boyfriend, 0, 770);
		var bfY:Float = num(stageFile.boyfriend, 1, 100);
		var gfX:Float = num(stageFile.girlfriend, 0, 400);
		var gfY:Float = num(stageFile.girlfriend, 1, 130);
		var dadX:Float = num(stageFile.opponent, 0, 100);
		var dadY:Float = num(stageFile.opponent, 1, 100);

		bfChar = tryChar(song.player1, true);
		dadChar = tryChar(song.player2, false);
		gfChar = (stageFile.hide_girlfriend == true) ? null : tryChar(song.gfVersion, false);

		// Si el oponente es una girlfriend, va a su posición (igual que en PlayState)
		var dadIsGF:Bool = (dadChar != null && dadChar.curCharacter.startsWith('gf'));
		if (dadIsGF)
		{
			dadX = gfX;
			dadY = gfY;
			gfChar = null;
		}

		if (bfChar != null) placeChar(bfChar, bfX, bfY);
		if (dadChar != null) placeChar(dadChar, dadX, dadY);
		if (gfChar != null) placeChar(gfChar, gfX, gfY);

		// Cajas de reemplazo si algún personaje no se pudo cargar
		if (bfChar != null) bfSpr = bfChar;
		else bfSpr = box(bfX, bfY, 0xFF2288FF);
		if (dadChar != null) dadSpr = dadChar;
		else dadSpr = box(dadX, dadY, 0xFFFF3377);
		if (gfChar != null) gfSpr = gfChar;
		else gfSpr = box(gfX, gfY, 0xFFFFCC33);

		// Objetos del stage (los que están definidos en el JSON); los personajes ocupan su sitio en la lista
		var added:Map<String, FlxSprite> = null;
		try
		{
			if (stageFile.objects != null)
				added = StageData.addObjectsToState(stageFile.objects, gfChar, dadChar, bfChar, worldGroup, true);
		}
		catch (e:Dynamic)
		{
			trace('No se pudieron cargar los objetos del stage: ' + e);
		}
		if (added == null) added = new Map();

		// Lo que no estaba en la lista de objetos se añade encima
		for (spr in [gfSpr, dadSpr, bfSpr])
		{
			if (!worldGroup.members.contains(spr)) worldGroup.add(spr);
		}
		worldGroup.cameras = [camWorld];
		add(worldGroup);

		// Puntos de cámara: BF (cian), oponente (magenta), GF (amarillo)
		var colors:Array<Int> = [0xFF00F0FF, 0xFFFF3DDC, 0xFFFFD84D];
		var names:Array<String> = ['BF', 'OPP', 'GF'];
		for (i in 0...3)
		{
			var m:FlxSprite = new FlxSprite().makeGraphic(44, 44, FlxColor.TRANSPARENT, true);
			FlxSpriteUtil.drawRect(m, 19, 2, 6, 40, colors[i]);
			FlxSpriteUtil.drawRect(m, 2, 19, 40, 6, colors[i]);
			m.antialiasing = true;
			markers.push(m);
			overlayGroup.add(m);

			var l:FlxText = new FlxText(0, 0, 0, names[i], 22);
			l.setFormat(fontPath, 22, colors[i], LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			l.borderSize = 2;
			markerLabels.push(l);
			overlayGroup.add(l);
		}

		eventMarker = new FlxSprite().makeGraphic(44, 44, FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRect(eventMarker, 19, 2, 6, 40, 0xFFFF8A1F);
		FlxSpriteUtil.drawRect(eventMarker, 2, 19, 40, 6, 0xFFFF8A1F);
		eventMarker.visible = false;
		overlayGroup.add(eventMarker);

		// Recuadro de lo que ve la cámara del juego (4 líneas)
		for (i in 0...4)
		{
			var line:FlxSprite = new FlxSprite().makeGraphic(1, 1, 0xFFFFFFFF);
			line.alpha = 0.9;
			vp.push(line);
			overlayGroup.add(line);
		}
		overlayGroup.cameras = [camWorld];
		add(overlayGroup);
	}

	function box(x:Float, y:Float, color:Int):FlxSprite
	{
		var b:FlxSprite = new FlxSprite(x, y).makeGraphic(220, 320, color);
		b.alpha = 0.55;
		return b;
	}

	function mid(spr:FlxSprite):FlxPoint
	{
		var m:FlxPoint = spr.getMidpoint();
		var r:FlxPoint = FlxPoint.get(m.x, m.y);
		m.put();
		return r;
	}

	function camPos(ch:Character, i:Int):Float
		return (ch != null && ch.cameraPosition != null && ch.cameraPosition.length > i) ? ch.cameraPosition[i] : 0;

	// Punto al que mira la cámara del juego (mismas fórmulas que PlayState.moveCamera)
	function targetPoint(which:Int):FlxPoint
	{
		var off:Array<Float>;
		var p:FlxPoint;
		switch (which)
		{
			case 0:
				off = stageFile.camera_boyfriend;
				p = mid(bfSpr);
				p.x = p.x - 100 - (camPos(bfChar, 0) - off[0]);
				p.y = p.y - 100 + (camPos(bfChar, 1) + off[1]);
			case 1:
				off = stageFile.camera_opponent;
				p = mid(dadSpr);
				p.x = p.x + 150 + camPos(dadChar, 0) + off[0];
				p.y = p.y - 100 + camPos(dadChar, 1) + off[1];
			default:
				off = stageFile.camera_girlfriend;
				p = mid(gfSpr);
				p.x = p.x + camPos(gfChar, 0) + off[0];
				p.y = p.y + camPos(gfChar, 1) + off[1];
		}
		return p;
	}

	// Coloca marcadores y recuadro según el estado actual
	function refreshWorld():Void
	{
		for (i in 0...3)
		{
			var p:FlxPoint = targetPoint(i);
			var inv:Float = 1 / previewZoom;
			markers[i].scale.set(inv, inv);
			markers[i].setPosition(p.x - markers[i].frameWidth / 2, p.y - markers[i].frameHeight / 2);
			markerLabels[i].scale.set(inv, inv);
			markerLabels[i].setPosition(p.x + 14 * inv, p.y - 28 * inv);
			if (i == viewTarget && mode == 0)
			{
				focusX = p.x;
				focusY = p.y;
			}
			p.put();
		}

		// Recuadro de la cámara del juego
		var cx:Float = focusX;
		var cy:Float = focusY;
		var zoom:Float = Math.max(0.05, stageFile.defaultZoom);
		var showRect:Bool = true;

		eventMarker.visible = false;
		if (mode == 1)
		{
			var ev:CamEvent = curEvent();
			showRect = false;
			if (ev != null && ev.sub[0] == 'Camera Follow Pos')
			{
				var x:Float = num(ev.sub, 1, Math.NaN);
				var y:Float = num(ev.sub, 2, Math.NaN);
				if (!Math.isNaN(x) && !Math.isNaN(y))
				{
					cx = x;
					cy = y;
					focusX = x;
					focusY = y;
					showRect = true;
					var inv:Float = 1 / previewZoom;
					eventMarker.scale.set(inv, inv);
					eventMarker.setPosition(x - eventMarker.frameWidth / 2, y - eventMarker.frameHeight / 2);
					eventMarker.visible = true;
				}
			}
		}

		var w:Float = FlxG.width / zoom;
		var h:Float = FlxG.height / zoom;
		var th:Float = 3 / previewZoom;
		for (l in vp) l.visible = showRect;
		vp[0].setGraphicSize(Std.int(w), Std.int(Math.max(1, th))); vp[0].updateHitbox(); vp[0].setPosition(cx - w / 2, cy - h / 2);
		vp[1].setGraphicSize(Std.int(w), Std.int(Math.max(1, th))); vp[1].updateHitbox(); vp[1].setPosition(cx - w / 2, cy + h / 2 - th);
		vp[2].setGraphicSize(Std.int(Math.max(1, th)), Std.int(h)); vp[2].updateHitbox(); vp[2].setPosition(cx - w / 2, cy - h / 2);
		vp[3].setGraphicSize(Std.int(Math.max(1, th)), Std.int(h)); vp[3].updateHitbox(); vp[3].setPosition(cx + w / 2 - th, cy - h / 2);
	}

	// ------------------------------------------------------------------ interfaz
	inline function ui<T:FlxBasic>(o:T):T
	{
		o.cameras = [camUI];
		add(o);
		return o;
	}

	function buildUI():Void
	{
		var aa:Bool = ClientPrefs.data.antialiasing;

		// Cabecera
		var panelTextX:Float;
		if (Paths.fileExists('images/freeplay/panel_right.png', AssetType.IMAGE))
		{
			rightPanel = new FlxSprite().loadGraphic(Paths.image('freeplay/panel_right'));
			rightPanel.antialiasing = aa;
			rightPanel.scale.set(s, s);
			rightPanel.updateHitbox();
			rightPanel.setPosition(W - rightPanel.width, 0);
			panelTextX = rightPanel.x + 49 * s;
		}
		else
		{
			rightPanel = new FlxSprite(W - 450, 0).makeGraphic(450, 72, FlxColor.BLACK);
			panelTextX = W - 450 + 54;
		}
		ui(rightPanel);
		var hdrY:Float = rightPanel.y;
		rightPanel.y = hdrY - rightPanel.height;
		FlxTween.tween(rightPanel, {y: hdrY}, 0.45, {startDelay: 0.1, ease: FlxEase.quartOut});

		titleText = new FlxText(panelTextX, 24 - rightPanel.height, 0, 'CAMERA EDITOR', 26);
		titleText.setFormat(fontPath, 26, FlxColor.WHITE, LEFT);
		ui(titleText);
		FlxTween.tween(titleText, {y: 24}, 0.45, {startDelay: 0.1, ease: FlxEase.quartOut});

		// Info arriba a la izquierda y ayuda abajo
		infoText = new FlxText(14, 14, W - rightPanel.width - 28, '', 20);
		infoText.setFormat(fontPath, 20, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		infoText.borderSize = 1.5;
		ui(infoText);

		hintText = new FlxText(14, H - 44, cardX - 28, '', 17);
		hintText.setFormat(fontPath, 17, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		hintText.alpha = 0.85;
		ui(hintText);

		msgText = new FlxText(14, H - 96, cardX - 28, '', 24);
		msgText.setFormat(fontPath, 24, 0xFFFFD84D, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		msgText.alpha = 0;
		ui(msgText);

		// Tarjeta de parámetros (derecha)
		var cardY:Float = CARD_Y * s;
		var cardH:Float = H - cardY - 16 * s;
		card = new FlxSprite(cardX, cardY).makeGraphic(Std.int(cardWpx), Std.int(cardH), FlxColor.BLACK);
		card.alpha = 0.7;
		ui(card);
		cardLeft = new FlxSprite(cardX, cardY).makeGraphic(3, Std.int(cardH), ACCENT);
		ui(cardLeft);
		cardTop = new FlxSprite(cardX, cardY).makeGraphic(Std.int(cardWpx), 2, ACCENT);
		ui(cardTop);

		cardTitle = new FlxText(cardX + 22 * s, cardY + 8 * s, 0, 'STAGE', 22);
		cardTitle.setFormat(fontPath, 22, ACCENT, LEFT);
		ui(cardTitle);

		cardSub = new FlxText(cardX + 22 * s, cardY + 36 * s, cardWpx - 40 * s, '', 16);
		cardSub.setFormat(fontPath, 16, FlxColor.WHITE, LEFT);
		ui(cardSub);

		cardSep = new FlxSprite(cardX + 14 * s, (LIST_TOP - 8) * s).makeGraphic(Std.int(cardWpx - 28 * s), 1, ACCENT);
		cardSep.alpha = 0.4;
		ui(cardSep);

		rowBar = new FlxSprite(cardX + 10 * s, 0).makeGraphic(Std.int(cardWpx - 20 * s), Std.int((ROW_H - 6) * s), ACCENT);
		rowBar.alpha = 0.18;
		ui(rowBar);
	}

	function clearRows():Void
	{
		for (t in rowLabels) { remove(t, true); t.destroy(); }
		for (t in rowValues) { remove(t, true); t.destroy(); }
		rowLabels = [];
		rowValues = [];
	}

	function setMode(m:Int):Void
	{
		mode = m;
		clearRows();
		curRow = 0;
		scroll = 0;
		holdTime = 0;

		rowIds = (mode == 0)
			? ['mode', 'target', 'pzoom', 'bfx', 'bfy', 'opx', 'opy', 'gfx', 'gfy', 'zoom', 'speed', 'save', 'reset']
			: ['mode', 'pzoom', 'evsel', 'evtype', 'evtime', 'ev1', 'ev2', 'evadd', 'evdel', 'evsave'];

		for (id in rowIds)
		{
			var isAction:Bool = (id == 'save' || id == 'reset' || id == 'evadd' || id == 'evdel' || id == 'evsave');
			var l:FlxText = new FlxText(0, 0, 0, rowLabel(id), 20);
			l.setFormat(fontPath, 20, isAction ? ACCENT : FlxColor.WHITE, LEFT);
			l.visible = false;
			l.cameras = [camUI];
			add(l);
			rowLabels.push(l);

			var v:FlxText = new FlxText(0, 0, 0, '', 22);
			v.setFormat(fontPath, 22, ACCENT, RIGHT);
			v.visible = false;
			v.cameras = [camUI];
			add(v);
			rowValues.push(v);
		}

		cardTitle.text = (mode == 0) ? 'STAGE' : 'EVENTS';
		cardSub.text = (mode == 0) ? stageName.toUpperCase() : (song.song != null ? song.song.toUpperCase() : '');
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
		refreshRows();
		refreshWorld();
		updateHint();
	}

	function rowLabel(id:String):String
	{
		return switch (id)
		{
			case 'mode': 'MODE';
			case 'target': 'VIEW TARGET';
			case 'pzoom': 'PREVIEW ZOOM';
			case 'bfx': 'BF CAMERA X';
			case 'bfy': 'BF CAMERA Y';
			case 'opx': 'OPP CAMERA X';
			case 'opy': 'OPP CAMERA Y';
			case 'gfx': 'GF CAMERA X';
			case 'gfy': 'GF CAMERA Y';
			case 'zoom': 'DEFAULT ZOOM';
			case 'speed': 'CAMERA SPEED';
			case 'save': '[ SAVE STAGE ]';
			case 'reset': '[ RELOAD FROM FILE ]';
			case 'evsel': 'EVENT';
			case 'evtype': 'TYPE';
			case 'evtime': 'TIME (MS)';
			case 'ev1': 'VALUE 1';
			case 'ev2': 'VALUE 2';
			case 'evadd': '[ ADD EVENT ]';
			case 'evdel': '[ DELETE EVENT ]';
			case 'evsave': returnToChart ? '[ BACK TO CHART ]' : '[ SAVE CHART FILE ]';
			default: id;
		}
	}

	function updateHint():Void
	{
		hintText.text = '[UP/DOWN] Row   [LEFT/RIGHT] Change (Y = x10)   [A] Action   [B] Back';
	}

	function showMsg(t:String):Void
	{
		msgText.text = t;
		msgText.alpha = 1;
		msgTimer = 2.5;
	}

	// ------------------------------------------------------------------ eventos de cámara
	function collectEvents():Void
	{
		camEvents = [];
		if (song.events == null) song.events = [];
		var allEvents:Array<Dynamic> = song.events;
		for (g in allEvents)
		{
			var group:Array<Dynamic> = g;
			if (group == null || group.length < 2) continue;
			var subs:Array<Dynamic> = group[1];
			if (subs == null) continue;
			for (sub in subs)
			{
				var sb:Array<Dynamic> = sub;
				if (sb != null && sb.length > 0 && CAM_NAMES.contains(Std.string(sb[0])))
					camEvents.push({group: group, sub: sb});
			}
		}
		camEvents.sort(function(a:CamEvent, b:CamEvent) return (num(a.group, 0, 0) < num(b.group, 0, 0)) ? -1 : 1);
		if (evSelected >= camEvents.length) evSelected = camEvents.length - 1;
		if (evSelected < 0) evSelected = 0;
	}

	function curEvent():CamEvent
		return (evSelected >= 0 && evSelected < camEvents.length) ? camEvents[evSelected] : null;

	function sortSongEvents():Void
	{
		var evs:Array<Dynamic> = song.events;
		evs.sort(function(a:Dynamic, b:Dynamic) return (num(a, 0, 0) < num(b, 0, 0)) ? -1 : 1);
	}

	// ------------------------------------------------------------------ valores
	function valueString(id:String):String
	{
		var ev:CamEvent = curEvent();
		return switch (id)
		{
			case 'mode': (mode == 0) ? 'STAGE' : 'EVENTS';
			case 'target': ['BF', 'OPPONENT', 'GIRLFRIEND'][viewTarget];
			case 'pzoom': Math.round(previewZoom * 100) + '%';
			case 'bfx': Std.string(round(stageFile.camera_boyfriend[0], 2));
			case 'bfy': Std.string(round(stageFile.camera_boyfriend[1], 2));
			case 'opx': Std.string(round(stageFile.camera_opponent[0], 2));
			case 'opy': Std.string(round(stageFile.camera_opponent[1], 2));
			case 'gfx': Std.string(round(stageFile.camera_girlfriend[0], 2));
			case 'gfy': Std.string(round(stageFile.camera_girlfriend[1], 2));
			case 'zoom': Std.string(round(stageFile.defaultZoom, 3));
			case 'speed': Std.string(round(stageFile.camera_speed, 2));
			case 'evsel': (camEvents.length < 1) ? '0 / 0' : ((evSelected + 1) + ' / ' + camEvents.length);
			case 'evtype': (ev != null) ? Std.string(ev.sub[0]) : '-';
			case 'evtime': (ev != null) ? Std.string(Math.round(num(ev.group, 0, 0))) : '-';
			case 'ev1': (ev != null) ? evValueText(ev, 1) : '-';
			case 'ev2': (ev != null) ? evValueText(ev, 2) : '-';
			default: '';
		}
	}

	function evValueText(ev:CamEvent, i:Int):String
	{
		var raw:Dynamic = (ev.sub.length > i) ? ev.sub[i] : null;
		var str:String = (raw == null) ? '' : Std.string(raw);
		if (str.length < 1) return '(blank)';
		return (str.length > 14) ? str.substr(0, 12) + '..' : str;
	}

	function refreshRows():Void
	{
		for (i in 0...rowIds.length)
			rowValues[i].text = valueString(rowIds[i]);

		var ev:CamEvent = curEvent();
		if (mode == 0)
		{
			var p:FlxPoint = targetPoint(viewTarget);
			infoText.text = 'STAGE: ' + stageName + '    CAMERA AT: ' + Math.round(p.x) + ', ' + Math.round(p.y) + '    ZOOM: ' + round(stageFile.defaultZoom, 3) + (stageDirty ? '    * UNSAVED' : '');
			p.put();
		}
		else
		{
			var desc:String = '';
			if (ev != null)
			{
				switch (Std.string(ev.sub[0]))
				{
					case 'Camera Follow Pos': desc = 'Follow X / Y. Blank values = back to normal.';
					case 'Add Camera Zoom': desc = 'Value 1 = game zoom add, Value 2 = HUD zoom add.';
					default: desc = 'Screen Shake: raw values (edit them in the chart).';
				}
			}
			infoText.text = 'SONG: ' + song.song + '    STAGE: ' + stageName + '\n' + desc;
		}
	}

	// ¿Es un valor numérico editable con IZQUIERDA / DERECHA?
	function evEditable(ev:CamEvent):Bool
	{
		var n:String = Std.string(ev.sub[0]);
		return (n == 'Camera Follow Pos' || n == 'Add Camera Zoom');
	}

	function adjust(id:String, dir:Int, mult:Float):Void
	{
		var ev:CamEvent = curEvent();
		switch (id)
		{
			case 'mode':
				setMode(1 - mode);
				return;
			case 'target':
				viewTarget = FlxMath.wrap(viewTarget + dir, 0, 2);
				panX = panY = 0;
			case 'pzoom':
				previewZoom = FlxMath.bound(round(previewZoom + dir * 0.05, 2), 0.1, 1.2);
				camWorld.zoom = previewZoom;
			case 'bfx': stageFile.camera_boyfriend[0] += dir * 10 * mult; stageDirty = true;
			case 'bfy': stageFile.camera_boyfriend[1] += dir * 10 * mult; stageDirty = true;
			case 'opx': stageFile.camera_opponent[0] += dir * 10 * mult; stageDirty = true;
			case 'opy': stageFile.camera_opponent[1] += dir * 10 * mult; stageDirty = true;
			case 'gfx': stageFile.camera_girlfriend[0] += dir * 10 * mult; stageDirty = true;
			case 'gfy': stageFile.camera_girlfriend[1] += dir * 10 * mult; stageDirty = true;
			case 'zoom':
				stageFile.defaultZoom = Math.max(0.05, round(stageFile.defaultZoom + dir * 0.01 * mult, 3));
				stageDirty = true;
			case 'speed':
				stageFile.camera_speed = Math.max(0, round(stageFile.camera_speed + dir * 0.1 * mult, 2));
				stageDirty = true;
			case 'evsel':
				if (camEvents.length > 0) evSelected = FlxMath.wrap(evSelected + dir, 0, camEvents.length - 1);
				panX = panY = 0;
			case 'evtype':
				if (ev != null)
				{
					var idx:Int = CAM_NAMES.indexOf(Std.string(ev.sub[0]));
					ev.sub[0] = CAM_NAMES[FlxMath.wrap(idx + dir, 0, CAM_NAMES.length - 1)];
					if (ev.sub[0] == 'Add Camera Zoom') { ev.sub[1] = '0.015'; ev.sub[2] = '0.03'; }
					else if (ev.sub[0] == 'Camera Follow Pos') { ev.sub[1] = Std.string(Math.round(focusX)); ev.sub[2] = Std.string(Math.round(focusY)); }
				}
			case 'evtime':
				if (ev != null)
				{
					var t:Float = Math.max(0, num(ev.group, 0, 0) + dir * 100 * mult);
					ev.group[0] = t;
					var keep:CamEvent = ev;
					sortSongEvents();
					collectEvents();
					for (i in 0...camEvents.length) if (camEvents[i].sub == keep.sub) evSelected = i;
				}
			case 'ev1' | 'ev2':
				if (ev != null && evEditable(ev))
				{
					var k:Int = (id == 'ev1') ? 1 : 2;
					var isFollow:Bool = (ev.sub[0] == 'Camera Follow Pos');
					var cur:Float = num(ev.sub, k, isFollow ? focusX : 0);
					cur += isFollow ? dir * 10 * mult : dir * 0.005 * mult;
					while (ev.sub.length <= k) ev.sub.push('');
					ev.sub[k] = Std.string(isFollow ? Math.round(cur) : round(cur, 3));
				}
			default:
				return;
		}
		refreshRows();
		refreshWorld();
	}

	function activate(id:String):Void
	{
		switch (id)
		{
			case 'save':
				saveStage();
			case 'reset':
				stageFile = StageData.getStageFile(stageName);
				fixStageFile();
				stageDirty = false;
				showMsg('Reloaded from file');
				refreshRows();
				refreshWorld();
			case 'evadd':
				var t:Float = (curEvent() != null) ? num(curEvent().group, 0, 0) : 0;
				var group:Array<Dynamic> = [t, [['Camera Follow Pos', Std.string(Math.round(focusX)), Std.string(Math.round(focusY))]]];
				song.events.push(group);
				sortSongEvents();
				collectEvents();
				for (i in 0...camEvents.length) if (camEvents[i].group == group) evSelected = i;
				showMsg('Event added');
				refreshRows();
				refreshWorld();
			case 'evdel':
				var ev:CamEvent = curEvent();
				if (ev == null) return;
				ev.group[1].remove(ev.sub);
				if (ev.group[1].length < 1) song.events.remove(ev.group);
				collectEvents();
				showMsg('Event deleted');
				refreshRows();
				refreshWorld();
			case 'evsave':
				if (returnToChart) leave();
				else saveChartFile();
			case 'mode':
				setMode(1 - mode);
			default:
		}
	}

	// ------------------------------------------------------------------ guardar
	function saveStage():Void
	{
		var data:String = Json.stringify(stageFile, null, '\t');
		var path:String = Paths.getPath('stages/' + stageName + '.json', TEXT, null, true);
		var done:Bool = false;
		try
		{
			#if MODS_ALLOWED
			if (!FileSystem.exists(path))
			{
				// El stage no existe como archivo: se crea dentro del mod actual
				var folder:String = Paths.mods((Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0 ? Mods.currentModDirectory + '/' : '') + 'stages/');
				if (!FileSystem.exists(folder)) FileSystem.createDirectory(folder);
				path = folder + stageName + '.json';
			}
			File.saveContent(path, data);
			done = true;
			#end
		}
		catch (e:Dynamic)
		{
			trace('Error al guardar el stage: ' + e);
		}

		if (!done)
		{
			#if mobile
			StorageUtil.saveContent(stageName + '.json', data);
			done = true;
			#end
		}

		if (done)
		{
			stageDirty = false;
			showMsg('Stage saved: ' + stageName + '.json');
		}
		else showMsg('ERROR: could not save the stage');
		refreshRows();
	}

	function saveChartFile():Void
	{
		var data:String = Json.stringify(song, null, '\t');
		var name:String = Paths.formatToSongPath(song.song) + '.json';
		try
		{
			#if mobile
			StorageUtil.saveContent(name, data);
			showMsg('Chart saved: ' + name);
			#else
			if (Song.chartPath != null) File.saveContent(Song.chartPath, data);
			else File.saveContent(name, data);
			showMsg('Chart saved');
			#end
		}
		catch (e:Dynamic)
		{
			showMsg('ERROR: could not save the chart');
		}
	}

	function leave():Void
	{
		FlxG.sound.play(Paths.sound('cancelMenu'));
		if (returnToChart) MusicBeatState.switchState(new ChartingState(false));
		else MusicBeatState.switchState(new MasterEditorMenu());
	}

	// ------------------------------------------------------------------ bucle
	override function update(elapsed:Float)
	{
		if (song == null)
		{
			if (controls.BACK) leave();
			super.update(elapsed);
			return;
		}

		animT += elapsed;
		introProg = Math.min(1, introProg + elapsed / 0.8);

		var mult:Float = (touchPad.buttonY.pressed || FlxG.keys.pressed.SHIFT) ? 10 : 1;

		// Fila
		if (controls.UI_UP_P) moveRow(-1);
		if (controls.UI_DOWN_P) moveRow(1);

		// Cambiar valor (mantener pulsado repite)
		var id:String = rowIds[curRow];
		var step:Int = 0;
		if (controls.UI_LEFT_P) { step = -1; holdTime = 0; }
		else if (controls.UI_RIGHT_P) { step = 1; holdTime = 0; }
		else if (controls.UI_LEFT || controls.UI_RIGHT)
		{
			var last:Int = Math.floor((holdTime - 0.4) * 14);
			holdTime += elapsed;
			var now:Int = Math.floor((holdTime - 0.4) * 14);
			if (holdTime > 0.4 && now - last > 0) step = controls.UI_LEFT ? -1 : 1;
		}
		if (step != 0) adjust(id, step, mult);

		if (controls.ACCEPT) activate(id);

		if (controls.BACK)
		{
			if (stageDirty && !leavePending)
			{
				leavePending = true;
				showMsg('UNSAVED STAGE CHANGES - press B again to leave');
			}
			else leave();
		}

		updatePreviewTouch();
		updateList(elapsed);
		updateAmbient(elapsed);

		super.update(elapsed);
	}

	function moveRow(d:Int):Void
	{
		curRow = FlxMath.wrap(curRow + d, 0, rowIds.length - 1);
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.3);
	}

	// Arrastrar con un dedo mueve la vista previa; pellizcar con dos dedos hace zoom
	function updatePreviewTouch():Void
	{
		var touches:Array<flixel.input.touch.FlxTouch> = [];
		for (t in FlxG.touches.list)
			if (t.pressed && t.screenX < cardX && t.screenY < H * 0.55 && t.screenY > 70 * s)
				touches.push(t);

		if (touches.length == 1)
		{
			var t:flixel.input.touch.FlxTouch = touches[0];
			if (!t.justPressed && dragging)
			{
				panX -= (t.screenX - dragLastX) / previewZoom;
				panY -= (t.screenY - dragLastY) / previewZoom;
			}
			dragLastX = t.screenX;
			dragLastY = t.screenY;
			dragging = true;
			pinchLast = -1;
		}
		else if (touches.length >= 2)
		{
			var dx:Float = touches[0].screenX - touches[1].screenX;
			var dy:Float = touches[0].screenY - touches[1].screenY;
			var d:Float = Math.sqrt(dx * dx + dy * dy);
			if (pinchLast > 0)
			{
				previewZoom = FlxMath.bound(previewZoom * (d / pinchLast), 0.1, 1.2);
				camWorld.zoom = previewZoom;
				refreshWorld();
				if (mode == 0) rowValues[rowIds.indexOf('pzoom')].text = valueString('pzoom');
			}
			pinchLast = d;
		}
		else
		{
			pinchLast = -1;
			dragging = false;
		}
	}

	function updateList(elapsed:Float):Void
	{
		var rowH:Float = ROW_H * s;
		var regionTop:Float = LIST_TOP * s;
		var regionH:Float = LIST_BOTTOM * s - regionTop;
		var maxScroll:Float = Math.max(0, rowIds.length * rowH - regionH);
		var target:Float = FlxMath.bound((curRow + 0.5) * rowH - regionH / 2, 0, maxScroll);
		scroll = FlxMath.lerp(target, scroll, Math.exp(-elapsed * 10));

		var ie:Float = FlxEase.quartOut(FlxMath.bound(introProg * 1.4, 0, 1));
		var off:Float = (1 - ie) * (cardWpx + 40 * s);

		card.x = cardLeft.x = cardTop.x = cardX + off;
		cardTitle.x = cardSub.x = cardX + 22 * s + off;
		cardSep.x = cardX + 14 * s + off;

		for (i in 0...rowIds.length)
		{
			var l:FlxText = rowLabels[i];
			var v:FlxText = rowValues[i];
			var y:Float = regionTop + i * rowH - scroll;
			var cyRow:Float = y + rowH / 2;
			var edge:Float = Math.min(cyRow - regionTop, regionTop + regionH - cyRow);
			l.visible = v.visible = edge > 0;
			if (!l.visible) continue;

			var isAction:Bool = (rowValues[i].text.length < 1);
			var sel:Bool = (i == curRow);
			var fade:Float = FlxMath.bound(edge / (rowH * 0.7), 0, 1);
			l.y = cyRow - l.height / 2;
			v.y = cyRow - v.height / 2;
			if (isAction) l.x = cardX + off + (cardWpx - l.width) / 2;
			else l.x = cardX + 22 * s + off;
			v.x = cardX + cardWpx - 22 * s - v.width + off;
			l.alpha = (sel ? 1 : 0.7) * fade * ie;
			v.alpha = (sel ? 1 : 0.8) * fade * ie;
		}

		var selY:Float = regionTop + curRow * rowH - scroll + 3 * s;
		rowBarY = FlxMath.lerp(selY, rowBarY, Math.exp(-elapsed * 18));
		rowBar.x = cardX + 10 * s + off;
		rowBar.y = rowBarY;
		rowBar.alpha = (0.2 + 0.08 * Math.sin(animT * 5)) * ie;
	}

	function updateAmbient(elapsed:Float):Void
	{
		// La vista previa sigue suavemente al punto elegido (más lo arrastrado con el dedo)
		var tx:Float = focusX + panX - camWorld.width / 2;
		var ty:Float = focusY + panY - camWorld.height / 2;
		camWorld.scroll.x = FlxMath.lerp(tx, camWorld.scroll.x, Math.exp(-elapsed * 8));
		camWorld.scroll.y = FlxMath.lerp(ty, camWorld.scroll.y, Math.exp(-elapsed * 8));

		if (msgTimer > 0)
		{
			msgTimer -= elapsed;
			if (msgTimer <= 0.5) msgText.alpha = Math.max(0, msgTimer / 0.5);
		}
	}
}
