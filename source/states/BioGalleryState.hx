package states;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.addons.display.FlxBackdrop;
import flixel.graphics.FlxGraphic;
import flixel.math.FlxPoint;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
import haxe.Json;
import mobile.backend.MobileData;
import mobile.backend.MobileScaleMode;
import objects.HealthIcon;
import objects.Neon;
import openfl.display.BitmapData;
import openfl.geom.Rectangle;
import openfl.utils.AssetType;

typedef BioEntry =
{
	var name:String;
	var icon:String;    // nombre del icono (images/icons/icon-NOMBRE.png)
	var image:String;   // retrato grande (images/RUTA.png). Si no existe, se muestra el icono grande
	var role:String;
	var bio:String;
	var details:String; // segunda página (datos)
	var accent:FlxColor;
}

/**
 * Galería de biografías estilo neón.
 * - Se llena desde data/bios.json (editable y compatible con mods).
 * - Abajo hay una tira de iconos: tocar/seleccionar un icono muestra su bio.
 * - A (o tocar la pestaña) cambia entre HISTORIA y DATOS.
 */
class BioGalleryState extends MusicBeatState
{
	public static var curSelected:Int = 0;

	var bios:Array<BioEntry> = [];
	var icons:Array<HealthIcon> = [];
	var iconCX:Array<Float> = [];

	var portraitPanel:FlxSprite;
	var portraitGlow:FlxSprite;
	var infoPanel:FlxSprite;
	var portrait:FlxSprite;
	var noImageText:FlxText;
	var bigIcon:HealthIcon;
	var iconFrame:FlxSprite;
	var divider:FlxSprite;
	var scanBar:FlxSprite;
	var ring:FlxSprite;
	var checker:FlxBackdrop;
	var checkSpeed:Float = 0;
	var ringCX:Float = 0;

	var nameText:FlxText;
	var roleText:FlxText;
	var tabText:FlxText;
	var bioText:FlxText;
	var counterText:FlxText;
	var leftArrow:FlxSprite;
	var rightArrow:FlxSprite;

	var page:Int = 0;
	var fullBio:String = '';
	var typed:Float = 0;
	var shown:Int = -1;
	var scanTime:Float = 0;
	var leaving:Bool = false;

	static inline var STRIP_Y:Float = 460;
	static inline var STRIP_H:Float = 120;
	static inline var MAX_SPACING:Float = 190;   // separacion maxima entre iconos
	static inline var MIN_SPACING:Float = 110;   // separacion minima (si hay muchos, la tira se desplaza)
	static inline var ARROW_MARGIN:Float = 80;   // espacio reservado para las flechas
	static inline var ICON_SEL:Float = 96;       // tamano (px) del icono seleccionado
	static inline var ICON_IDLE:Float = 62;      // tamano (px) de los demas
	static inline var ICON_BIG:Float = 88;       // tamano (px) del icono junto al nombre

	override function create()
	{
		super.create();

		#if MODS_ALLOWED
		Mods.pushGlobalMods();
		#end
		Mods.loadTopMod();

		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Leyendo biografias", null);
		#end

		persistentUpdate = persistentDraw = true;

		loadBios();
		if (curSelected >= bios.length) curSelected = 0;

		var wx:Float = Neon.wideX();
		var ww:Int = Neon.wideW();

		// ---- Fondo ----
		var bg:FlxSprite = Neon.gradient(ww, FlxG.height);
		bg.x = wx;
		add(bg);
		makeChecker();
		add(Neon.scanlines(ww, FlxG.height, wx));

		// ---- Titulo ----
		var title:FlxText = Neon.styleText(new FlxText(wx + 60, 20, 0, 'ARCHIVO DE PERSONAJES'), Neon.MAGENTA, 34);
		add(title);

		counterText = Neon.styleText(new FlxText(0, 84, 0, ''), Neon.CYAN, 24);
		add(counterText);

		var line:FlxSprite = new FlxSprite(wx + 60, 74).makeGraphic(ww - 120, 3, Neon.CYAN);
		line.alpha = 0.8;
		add(line);

		// ---- Paneles ----
		portraitPanel = Neon.panel(300, 350, Neon.CYAN);
		portraitPanel.setPosition(70, 95);
		add(portraitPanel);

		portraitGlow = new FlxSprite(portraitPanel.x + 8, portraitPanel.y + 8).makeGraphic(284, 334, FlxColor.WHITE);
		portraitGlow.alpha = 0.1;
		add(portraitGlow);

		infoPanel = Neon.panel(810, 350, Neon.MAGENTA);
		infoPanel.setPosition(400, 95);
		add(infoPanel);

		portrait = new FlxSprite();
		add(portrait);

		noImageText = Neon.styleText(new FlxText(portraitPanel.x, portraitPanel.y + 160, portraitPanel.width, 'SIN IMAGEN'), Neon.DIM, 22);
		noImageText.alignment = CENTER;
		noImageText.visible = false;
		add(noImageText);

		scanBar = new FlxSprite(portraitPanel.x + 8, portraitPanel.y + 10).makeGraphic(Std.int(portraitPanel.width) - 16, 3, Neon.CYAN);
		scanBar.alpha = 0.35;
		add(scanBar);

		// ---- Info: icono + nombre ----
		iconFrame = new FlxSprite(infoPanel.x + 24, infoPanel.y + 18).makeGraphic(110, 110, FlxColor.TRANSPARENT, true);
		add(iconFrame);

		nameText = Neon.styleText(new FlxText(infoPanel.x + 156, infoPanel.y + 24, 520, ''), Neon.MAGENTA, 44);
		add(nameText);

		roleText = Neon.styleText(new FlxText(infoPanel.x + 158, infoPanel.y + 80, 520, ''), Neon.CYAN, 22);
		add(roleText);

		tabText = Neon.styleText(new FlxText(infoPanel.x + infoPanel.width - 190, infoPanel.y + 26, 160, 'HISTORIA'), Neon.CYAN, 22);
		tabText.alignment = RIGHT;
		add(tabText);

		divider = new FlxSprite(infoPanel.x + 26, infoPanel.y + 148).makeGraphic(Std.int(infoPanel.width) - 52, 2, FlxColor.WHITE);
		divider.alpha = 0.6;
		add(divider);

		bioText = new FlxText(infoPanel.x + 28, infoPanel.y + 164, infoPanel.width - 56, '');
		bioText.setFormat(Paths.font('vcr.ttf'), 24, Neon.TEXT, LEFT);
		add(bioText);

		// ---- Tira de iconos ----
		var stripPanel:FlxSprite = Neon.panel(ww - 60, Std.int(STRIP_H), Neon.BLUE);
		stripPanel.setPosition(wx + 30, STRIP_Y);
		add(stripPanel);

		var cy:Float = STRIP_Y + STRIP_H / 2;

		ring = new FlxSprite(0, cy - 62).makeGraphic(124, 124, FlxColor.TRANSPARENT, true);
		add(ring);

		for (i in 0...bios.length)
		{
			var ic:HealthIcon = new HealthIcon(bios[i].icon);
			ic.origin.set(ic.frameWidth * 0.5, ic.frameHeight * 0.5);
			var s:Float = ICON_IDLE / Math.max(ic.frameWidth, ic.frameHeight);
			ic.scale.set(s, s);
			add(ic);
			icons.push(ic);
			iconCX.push(stripTargetX(i));
			placeIcon(ic, iconCX[i], cy);
		}
		ringCX = stripTargetX(curSelected);

		// ---- Flechas (chevrones dibujados, no dependen de la fuente) ----
		leftArrow = makeArrow(true);
		leftArrow.setPosition(wx + 30 + 24, cy - leftArrow.height / 2);
		rightArrow = makeArrow(false);
		rightArrow.setPosition(wx + ww - 30 - 24 - rightArrow.width, cy - rightArrow.height / 2);
		add(leftArrow);
		add(rightArrow);

		selectIndex(curSelected, true);

		addSafePad();
	}

	// ------------------------------------------------------------------
	// Utilidades de interfaz
	// ------------------------------------------------------------------

	// Usa solo modos de touchpad que existen (evita el error "actionMode doesn't exist")
	function addSafePad():Void
	{
		var dpad:String = 'NONE';
		for (m in ['LEFT_RIGHT', 'LEFT_FULL', 'UP_LEFT_RIGHT', 'FULL'])
			if (MobileData.dpadModes.exists(m)) { dpad = m; break; }

		var action:String = 'NONE';
		for (m in ['A_B', 'A_B_X_Y', 'A_B_C_X_Y'])
			if (MobileData.actionModes.exists(m)) { action = m; break; }

		addTouchPad(dpad, action);
	}

	// Fondo de cuadros animado: usa el mismo PNG del Freeplay (images/freeplay/check.png o checker.png).
	// Si no se encuentra, dibuja uno propio para que SIEMPRE se vea.
	function makeChecker():Void
	{
		var imgScale:Float = FlxG.height / 720;
		var graphic:FlxGraphic = null;

		for (k in ['freeplay/check', 'freeplay/checker'])
		{
			if (Paths.fileExists('images/' + k + '.png', AssetType.IMAGE))
			{
				graphic = Paths.image(k);
				break;
			}
		}

		if (graphic == null)
		{
			var tile:Int = 64;
			var bmp:BitmapData = new BitmapData(tile * 2, tile * 2, true, 0x00000000);
			bmp.fillRect(new Rectangle(0, 0, tile, tile), 0xFFFFFFFF);
			bmp.fillRect(new Rectangle(tile, tile, tile, tile), 0xFFFFFFFF);
			graphic = FlxGraphic.fromBitmapData(bmp, false, 'bio_checker_fallback');
		}

		checker = new FlxBackdrop(graphic, XY);
		checker.antialiasing = ClientPrefs.data.antialiasing;
		checker.scale.set(imgScale * 1.4, imgScale * 1.4);
		checker.updateHitbox();
		checker.alpha = 0.22;
		checker.scrollFactor.set();
		checkSpeed = 34 * imgScale;
		add(checker);
	}

	function makeArrow(left:Bool):FlxSprite
	{
		var w:Int = 44;
		var h:Int = 64;
		var spr:FlxSprite = new FlxSprite().makeGraphic(w, h, FlxColor.TRANSPARENT, true);
		var pts:Array<FlxPoint> = left
			? [FlxPoint.get(34, 0), FlxPoint.get(44, 10), FlxPoint.get(16, 32), FlxPoint.get(44, 54), FlxPoint.get(34, 64), FlxPoint.get(0, 32)]
			: [FlxPoint.get(10, 0), FlxPoint.get(0, 10), FlxPoint.get(28, 32), FlxPoint.get(0, 54), FlxPoint.get(10, 64), FlxPoint.get(44, 32)];
		FlxSpriteUtil.drawPolygon(spr, pts, FlxColor.WHITE);
		spr.color = Neon.MAGENTA;
		return spr;
	}

	// Centro X de cada icono dentro de la tira: reparte los iconos entre las dos flechas.
	// Si no caben, la tira se desplaza para mantener visible el seleccionado.
	function stripTargetX(i:Int):Float
	{
		var wx:Float = Neon.wideX();
		var ww:Float = Neon.wideW();
		var left:Float = wx + 30 + ARROW_MARGIN + 30;
		var right:Float = wx + ww - 30 - ARROW_MARGIN - 30;
		var avail:Float = right - left;
		var n:Int = bios.length;

		var sp:Float = Math.min(MAX_SPACING, avail / n);
		if (sp < MIN_SPACING) sp = MIN_SPACING;

		var total:Float = sp * n;
		var base:Float = left + sp * 0.5 + i * sp;
		if (total <= avail) return base + (avail - total) * 0.5;

		var baseSel:Float = left + sp * 0.5 + curSelected * sp;
		var scroll:Float = Math.max(0, Math.min(total - avail, baseSel - (left + right) * 0.5));
		return base - scroll;
	}

	// Coloca el CENTRO VISUAL del icono en (cx, cy), sin depender de offsets/hitbox de HealthIcon
	inline function placeIcon(ic:HealthIcon, cx:Float, cy:Float):Void
		ic.setPosition(cx - ic.origin.x + ic.offset.x, cy - ic.origin.y + ic.offset.y);

	inline function sizeScale(ic:HealthIcon, size:Float):Float
		return size / Math.max(ic.frameWidth, ic.frameHeight);

	inline function mouseNear(cx:Float, cy:Float, halfW:Float, halfH:Float):Bool
	{
		var mp:FlxPoint = FlxG.mouse.getWorldPosition(FlxG.camera);
		var hit:Bool = Math.abs(mp.x - cx) <= halfW && Math.abs(mp.y - cy) <= halfH;
		mp.put();
		return hit;
	}

	// ------------------------------------------------------------------
	// Datos
	// ------------------------------------------------------------------

	function loadBios():Void
	{
		var loaded:Bool = false;
		try
		{
			if (Paths.fileExists('data/bios.json', AssetType.TEXT))
			{
				var data:Dynamic = Json.parse(Paths.getTextFromFile('data/bios.json'));
				var list:Array<Dynamic> = data.characters;
				for (e in list)
				{
					var idx:Int = bios.length;
					var acc:FlxColor = Neon.accentFor(idx);
					if (e.color != null)
					{
						var parsed:Null<FlxColor> = FlxColor.fromString(Std.string(e.color));
						if (parsed != null)
						{
							acc = parsed;
							acc.alpha = 255;
						}
					}

					var det:String = '';
					if (e.details != null)
					{
						var arr:Array<Dynamic> = e.details;
						det = arr.join('\n');
					}

					bios.push({
						name: (e.name != null) ? Std.string(e.name) : '???',
						icon: (e.icon != null) ? Std.string(e.icon) : 'face',
						image: (e.image != null) ? Std.string(e.image) : 'bio/' + ((e.icon != null) ? Std.string(e.icon) : 'face'),
						role: (e.role != null) ? Std.string(e.role) : '',
						bio: (e.bio != null) ? Std.string(e.bio) : '',
						details: det,
						accent: acc
					});
					loaded = true;
				}
			}
		}
		catch (e:Dynamic)
		{
			trace('bios.json tiene un error: ' + e);
			loaded = false;
		}

		if (!loaded || bios.length == 0)
		{
			bios = [];
			bios.push(make('Boyfriend', 'bf', 'Rapero / Protagonista',
				'Un chico con gorra y mucho ritmo que enfrenta a cualquiera que se le ponga enfrente en una batalla de rap, todo por el amor de Girlfriend.',
				'Edad: 16\nDuo: Girlfriend\nHabilidad: Beat Box', Neon.CYAN));
			bios.push(make('Girlfriend', 'gf', 'Novia de Boyfriend / DJ',
				'Siempre esta sentada sobre las bocinas llevando el ritmo de cada cancion. Aunque no lo parezca, es quien mantiene todo el espectaculo en pie.',
				'Edad: 16\nDuo: Boyfriend\nLugar favorito: Sobre las bocinas', Neon.MAGENTA));
			bios.push(make('Daddy Dearest', 'dad', 'Ex estrella del rock',
				'Padre de Girlfriend y exestrella del rock. No soporta que su hija salga con un chico que solo sabe hacer ruido con un microfono.',
				'Hija: Girlfriend\nEsposa: Mommy Mearest', 0xFFAF66CE));
		}
	}

	function make(name:String, icon:String, role:String, bio:String, details:String, accent:FlxColor):BioEntry
	{
		return {
			name: name,
			icon: icon,
			image: 'bio/' + icon,
			role: role,
			bio: bio,
			details: details,
			accent: accent
		};
	}

	// ------------------------------------------------------------------
	// Seleccion
	// ------------------------------------------------------------------

	function changeItem(change:Int):Void
	{
		selectIndex(FlxMath.wrap(curSelected + change, 0, bios.length - 1));
	}

	function selectIndex(idx:Int, silent:Bool = false):Void
	{
		curSelected = idx;
		page = 0;
		var b:BioEntry = bios[idx];

		if (!silent)
			FlxG.sound.play(Paths.sound('scrollMenu'));

		drawRing(b.accent);
		drawIconFrame(b.accent);

		nameText.text = b.name.toUpperCase();
		nameText.borderColor = b.accent;
		roleText.text = b.role;

		FlxTween.cancelTweensOf(divider);
		FlxTween.cancelTweensOf(portraitGlow);
		if (silent)
		{
			divider.color = b.accent;
			portraitGlow.color = b.accent;
		}
		else
		{
			FlxTween.color(divider, 0.25, divider.color, b.accent);
			FlxTween.color(portraitGlow, 0.25, portraitGlow.color, b.accent);
		}

		counterText.text = pad(idx + 1) + ' / ' + pad(bios.length);
		counterText.x = Neon.wideX() + Neon.wideW() - 60 - counterText.width;
		counterText.y = 84; // debajo de la linea, lejos del contador de FPS

		FlxTween.cancelTweensOf(checker);
		FlxTween.cancelTweensOf(leftArrow);
		FlxTween.cancelTweensOf(rightArrow);
		if (silent)
		{
			checker.color = b.accent;
			leftArrow.color = b.accent;
			rightArrow.color = b.accent;
		}
		else
		{
			FlxTween.color(checker, 0.25, checker.color, b.accent);
			FlxTween.color(leftArrow, 0.25, leftArrow.color, b.accent);
			FlxTween.color(rightArrow, 0.25, rightArrow.color, b.accent);
		}

		loadPortrait(b);
		showPage();
	}

	function showPage():Void
	{
		var b:BioEntry = bios[curSelected];
		tabText.text = (page == 0) ? 'HISTORIA' : 'DATOS';
		fullBio = (page == 0) ? b.bio : (b.details != '' ? b.details : 'Sin datos registrados.');

		// Ajusta el tamano de letra para que el texto quepa en el panel (vcr es monoespaciada)
		var sz:Int = 24;
		while (sz > 16)
		{
			var cpl:Int = Std.int(bioText.fieldWidth / (sz * 0.62));
			var lines:Int = Math.ceil(fullBio.length / Math.max(1, cpl)) + (fullBio.split('\n').length - 1);
			if (lines * sz * 1.25 <= 170) break;
			sz--;
		}
		bioText.size = sz;

		typed = 0;
		shown = -1;
		bioText.text = '';
	}

	function togglePage():Void
	{
		page = (page == 0) ? 1 : 0;
		FlxG.sound.play(Paths.sound('confirmMenu'), 0.6);
		showPage();
	}

	function loadPortrait(b:BioEntry):Void
	{
		// Icono del personaje (siempre se muestra junto al nombre)
		if (bigIcon != null)
		{
			remove(bigIcon, true);
			bigIcon.destroy();
			bigIcon = null;
		}
		bigIcon = new HealthIcon(b.icon);
		bigIcon.origin.set(bigIcon.frameWidth * 0.5, bigIcon.frameHeight * 0.5);
		var bs:Float = sizeScale(bigIcon, ICON_BIG);
		bigIcon.scale.set(bs, bs);
		placeIcon(bigIcon, iconFrame.x + iconFrame.width / 2, iconFrame.y + iconFrame.height / 2);
		bigIcon.alpha = 0;
		add(bigIcon);
		FlxTween.tween(bigIcon, {alpha: 1}, 0.25);

		// PNG grande del personaje
		FlxTween.cancelTweensOf(portrait);
		if (b.image != '' && Paths.fileExists('images/' + b.image + '.png', AssetType.IMAGE))
		{
			noImageText.visible = false;
			portrait.visible = true;
			portrait.loadGraphic(Paths.image(b.image));
			var s:Float = Math.min((portraitPanel.width - 40) / portrait.frameWidth, (portraitPanel.height - 40) / portrait.frameHeight);
			portrait.scale.set(s, s);
			portrait.updateHitbox();
			portrait.antialiasing = ClientPrefs.data.antialiasing;
			portrait.setPosition(portraitPanel.x + (portraitPanel.width - portrait.width) / 2,
				portraitPanel.y + (portraitPanel.height - portrait.height) / 2);

			// Entrada suave
			var tx:Float = portrait.x;
			portrait.x = tx - 30;
			portrait.alpha = 0;
			FlxTween.tween(portrait, {alpha: 1, x: tx}, 0.3, {ease: FlxEase.quadOut});
		}
		else
		{
			portrait.visible = false;
			noImageText.visible = true;
		}
	}

	function drawIconFrame(color:FlxColor):Void
	{
		FlxSpriteUtil.fill(iconFrame, FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(iconFrame, 2, 2, 106, 106, 16, 16, 0x44000000, {thickness: 3, color: color});
	}

	function drawRing(color:FlxColor):Void
	{
		FlxSpriteUtil.fill(ring, FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawRoundRect(ring, 2, 2, 120, 120, 18, 18, 0x22FFFFFF, {thickness: 3, color: color});
	}

	inline function pad(n:Int):String
		return (n < 10 ? '0' : '') + n;

	inline function lerpTo(a:Float, b:Float, t:Float):Float
		return a + (b - a) * Math.min(1, t);

	// ------------------------------------------------------------------
	// Update
	// ------------------------------------------------------------------

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		// Barra de escaneo del retrato
		scanTime += elapsed;
		scanBar.y = portraitPanel.y + 10 + ((scanTime * 110) % (portraitPanel.height - 24));

		// Fondo de cuadros en movimiento
		checker.x += checkSpeed * elapsed;
		checker.y += checkSpeed * elapsed;

		// Iconos de la tira
		var wx:Float = Neon.wideX();
		var ww:Float = Neon.wideW();
		var cy:Float = STRIP_Y + STRIP_H / 2;
		var viewL:Float = wx + 30 + ARROW_MARGIN;
		var viewR:Float = wx + ww - 30 - ARROW_MARGIN;
		for (i in 0...icons.length)
		{
			var ic:HealthIcon = icons[i];
			var isSel:Bool = (i == curSelected);

			iconCX[i] = lerpTo(iconCX[i], stripTargetX(i), elapsed * 12);

			var sc:Float = lerpTo(ic.scale.x, sizeScale(ic, isSel ? ICON_SEL : ICON_IDLE), elapsed * 14);
			ic.scale.set(sc, sc);
			placeIcon(ic, iconCX[i], cy);

			var inView:Bool = iconCX[i] >= viewL && iconCX[i] <= viewR;
			ic.alpha = inView ? (isSel ? 1 : 0.6) : 0;
		}

		// Marco de seleccion: sigue al icono elegido
		ringCX = lerpTo(ringCX, stripTargetX(curSelected), elapsed * 14);
		ring.setPosition(ringCX - ring.width / 2, cy - ring.height / 2);

		// Flechas: palpitan suavemente
		var pulse:Float = 0.75 + 0.25 * Math.sin(scanTime * 5);
		leftArrow.alpha = pulse;
		rightArrow.alpha = pulse;

		// Texto que se escribe poco a poco
		if (shown < fullBio.length)
		{
			typed += elapsed * 140;
			var n:Int = Std.int(Math.min(fullBio.length, typed));
			if (n != shown)
			{
				shown = n;
				bioText.text = fullBio.substr(0, n);
			}
		}

		if (leaving) return;

		// Teclado / botones tactiles
		if (controls.UI_LEFT_P) changeItem(-1);
		if (controls.UI_RIGHT_P) changeItem(1);
		if (controls.ACCEPT) togglePage();

		if (controls.BACK)
		{
			leaving = true;
			FlxG.sound.play(Paths.sound('cancelMenu'));
			MusicBeatState.switchState(new MainMenuState());
			return;
		}

		// Toque / mouse (areas de toque manuales: no dependen del hitbox de los sprites)
		if (FlxG.mouse.justPressed)
		{
			var cy2:Float = STRIP_Y + STRIP_H / 2;
			if (mouseNear(leftArrow.x + leftArrow.width / 2, cy2, 60, 70)) { changeItem(-1); return; }
			if (mouseNear(rightArrow.x + rightArrow.width / 2, cy2, 60, 70)) { changeItem(1); return; }
			if (mouseNear(tabText.x + tabText.fieldWidth / 2, tabText.y + 14, tabText.fieldWidth / 2 + 30, 34)) { togglePage(); return; }

			for (i in 0...icons.length)
			{
				if (icons[i].alpha > 0.1 && mouseNear(iconCX[i], cy2, 50, STRIP_H / 2))
				{
					if (i == curSelected) togglePage();
					else selectIndex(i);
					break;
				}
			}
		}
	}
}
