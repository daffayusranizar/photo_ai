const functions = require("firebase-functions");
const admin = require("firebase-admin");
const { GoogleGenerativeAI } = require("@google/generative-ai");
const { GoogleGenAI, Modality } = require("@google/genai");

admin.initializeApp();

const GEN_AI_KEY = functions.config().gemini.key;

async function imageUrlToBase64(url) {
  const fetch = (await import('node-fetch')).default;
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to fetch image: ${response.status} ${response.statusText}`);
  }
  const buffer = Buffer.from(await response.arrayBuffer());
  return buffer.toString("base64");
}

// Helper function to add delay
function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// Retry logic with exponential backoff
async function retryWithBackoff(fn, maxRetries = 3, initialDelay = 1000) {
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      const isRateLimitError = error.message && (
        error.message.includes('429') ||
        error.message.includes('RESOURCE_EXHAUSTED')
      );

      if (!isRateLimitError || attempt === maxRetries - 1) {
        throw error;
      }

      const delay = initialDelay * Math.pow(2, attempt);
      console.log(`⏳ Rate limit hit, retrying in ${delay}ms (attempt ${attempt + 1}/${maxRetries})...`);
      await sleep(delay);
    }
  }
}

// ============================================================================
// LIGHTING PROFILES - Technical photography parameters by time of day
// ============================================================================
const lightingProfiles = {
  sunrise: {
    colorTemp: "3000-4000K warm orange-golden",
    iso: "100-200",
    shadowType: "long soft shadows stretching away from light source",
    skyDescription: "gradient sky with orange, pink, and purple tones near horizon, transitioning to lighter blue above",
    lightDirection: "low angle side lighting from horizon, creating dramatic rim light",
    contrast: "medium-low with warm highlights and cool blue shadows",
    specialNotes: "golden rim lighting on edges, cool blue ambient in shadow areas, magical quality",
    grainLevel: "minimal, clean image",
    exposure: "well-exposed with detail in both highlights and shadows"
  },

  morning: {
    colorTemp: "5000-5500K neutral warm",
    iso: "100-200",
    shadowType: "medium-length crisp shadows with defined edges",
    skyDescription: "clear bright blue sky or soft white clouds, fresh atmosphere",
    lightDirection: "moderate angle from above, pleasant directional light",
    contrast: "medium contrast, balanced and natural",
    specialNotes: "fresh clean light, good visibility, comfortable brightness",
    grainLevel: "none, very clean",
    exposure: "bright and evenly exposed"
  },

  noon: {
    colorTemp: "5500-6500K cool white",
    iso: "100",
    shadowType: "short hard shadows directly below subject, very dark and sharp-edged",
    skyDescription: "bright washed-out sky, possibly hazy white-blue",
    lightDirection: "harsh overhead lighting from directly above",
    contrast: "high contrast with bright highlights and deep shadows",
    specialNotes: "squinting eyes acceptable, harsh unflattering light, very bright overall",
    grainLevel: "none, maximum sharpness",
    exposure: "very bright, possible slight overexposure in highlights"
  },

  afternoon: {
    colorTemp: "4500-5500K slightly warm",
    iso: "100-200",
    shadowType: "medium shadows beginning to lengthen, softer edges than noon",
    skyDescription: "clear blue sky with depth, pleasant atmosphere",
    lightDirection: "moderate angle, light becoming warmer and more flattering",
    contrast: "medium contrast, comfortable range",
    specialNotes: "pleasant lighting conditions, natural and comfortable",
    grainLevel: "minimal",
    exposure: "well-balanced natural exposure"
  },

  sunset: {
    colorTemp: "2500-3500K warm golden-amber",
    iso: "200-400",
    shadowType: "long soft warm-toned shadows, very flattering",
    skyDescription: "dramatic gradient with orange, red, pink, purple tones, golden hour glow",
    lightDirection: "low angle golden light, side or back lighting creates glow",
    contrast: "medium-low with warm wrap-around light",
    specialNotes: "golden glow on skin, rim lighting, warm atmospheric haze, magical quality",
    grainLevel: "slight grain starting to appear",
    exposure: "warm glowing exposure, rich colors"
  },

  blue_hour: {
    colorTemp: "8000-12000K cool blue-purple",
    iso: "400-800",
    shadowType: "very soft minimal shadows, diffused ambient light",
    skyDescription: "deep blue twilight sky with residual color, ethereal atmosphere",
    lightDirection: "soft diffused ambient light from sky, no direct sun",
    contrast: "low contrast, soft transitions",
    specialNotes: "magical blue twilight glow, soft dreamy quality, artificial lights beginning to glow warmly",
    grainLevel: "visible fine grain",
    exposure: "slightly underexposed for mood, artificial lights properly exposed"
  },

  night: {
    colorTemp: "mixed 3000K warm streetlights and 6500K cool LED signs",
    iso: "800-3200",
    shadowType: "multiple sharp shadows from different artificial light sources",
    skyDescription: "dark blue-black night sky, possibly city light pollution orange glow",
    lightDirection: "multiple point light sources - streetlights, shop windows, signs",
    contrast: "very high contrast with bright pools of light and dark shadows",
    specialNotes: "visible noise/grain, mixed color temperatures, dramatic lighting, bright artificial lights with dark areas between",
    grainLevel: "clearly visible grain and noise, typical of high ISO phone photos at night",
    exposure: "balanced for artificial lights, some areas dark, highlights bright"
  }
};

// ============================================================================
// PLACE MODIFIERS - Location-specific lighting and environmental characteristics
// ============================================================================
const placeModifiers = {
  cafe: {
    indoorOutdoor: "outdoor",
    reflectiveSurfaces: "polished marble or metal table surfaces reflecting light",
    exposureAdjustment: "balanced, mix of shade and ambient light",
    colorCast: "warm tones from café ambiance, earthy furniture colors",
    specialLighting: "dappled shade from café awning or umbrella, natural ambient street light",
    atmosphericConditions: "urban atmosphere, slight warmth from surrounding activity",
    groundSurface: "sidewalk pavement or outdoor café flooring",
    depthElements: "café chairs and tables nearby, other patrons blurred in background, storefront behind"
  },

  mountain: {
    indoorOutdoor: "outdoor",
    reflectiveSurfaces: "none, matte natural surfaces",
    exposureAdjustment: "bright, high altitude means more intense sunlight and deeper blue sky",
    colorCast: "cool blue from sky, possibly warm earth tones from rocks",
    specialLighting: "crisp clear light, thinner atmosphere, very sharp shadows",
    atmosphericConditions: "crystal clear air, distant atmospheric haze on far peaks, cooler color temperature",
    groundSurface: "rocky terrain, dirt trail, scattered stones and vegetation",
    depthElements: "layered mountain peaks in background with atmospheric perspective, pine trees, hiking trail visible"
  },

  beach: {
    indoorOutdoor: "outdoor",
    reflectiveSurfaces: "strong light reflection from wet sand and water surface, creates fill light from below",
    exposureAdjustment: "very bright, may need slight underexposure to prevent blown highlights",
    colorCast: "blue from ocean and sky, warm golden from sand",
    specialLighting: "intense brightness, water acts as giant reflector providing fill light, possible rim light from water reflections",
    atmosphericConditions: "bright open atmosphere, possible salty haze, warm sandy environment",
    groundSurface: "sandy beach with texture, possibly wet sand near water, footprints visible",
    depthElements: "ocean waves in background, horizon line, scattered shells or beach debris, distant shoreline"
  },

  luxury_car: {
    indoorOutdoor: "outdoor",
    reflectiveSurfaces: "highly reflective car paint, chrome details, glass windows reflecting environment",
    exposureAdjustment: "careful balance to avoid reflections blowing out",
    colorCast: "metallic sheen from car, urban gray tones",
    specialLighting: "specular highlights on car surface, reflections of sky and surroundings in paint",
    atmosphericConditions: "urban environment, clean modern setting",
    groundSurface: "smooth pavement or concrete, possibly polished show floor",
    depthElements: "car prominent in frame, city buildings or urban background, street elements"
  },

  city_street: {
    indoorOutdoor: "outdoor",
    reflectiveSurfaces: "shop windows, glass building facades, wet pavement if recent rain",
    exposureAdjustment: "varies by time - bright midday or artificial lights at night",
    colorCast: "urban neutral grays, possibly warm from brick buildings",
    specialLighting: "building shadows creating contrast zones, reflected light from windows and facades",
    atmosphericConditions: "urban atmosphere, possible slight haze",
    groundSurface: "concrete sidewalk, street pavement, urban textures",
    depthElements: "buildings lining street, pedestrians blurred in background, storefronts, street signs, urban details"
  },

  forest: {
    indoorOutdoor: "outdoor",
    reflectiveSurfaces: "minimal, matte natural surfaces, possibly wet leaves reflecting",
    exposureAdjustment: "darker than open areas, dappled light creates high contrast patches",
    colorCast: "green tint from foliage, cool forest shadows",
    specialLighting: "dappled sunlight filtering through tree canopy, god rays possible, soft diffused light in shade",
    atmosphericConditions: "filtered light, cooler temperature, fresh forest air quality",
    groundSurface: "forest floor with dirt path, fallen leaves, roots, natural debris",
    depthElements: "tree trunks framing, layered foliage depth, filtered light patches, natural forest density"
  },

  lake: {
    indoorOutdoor: "outdoor",
    reflectiveSurfaces: "calm water surface creating mirror reflections, fill light from water",
    exposureAdjustment: "bright from water reflection, balanced exposure needed",
    colorCast: "blue from water and sky, possibly green from surrounding vegetation",
    specialLighting: "soft fill light reflected from water surface, possible sparkle on water",
    atmosphericConditions: "open peaceful atmosphere, fresh water environment",
    groundSurface: "natural shoreline - grass, rocks, sand, or dock",
    depthElements: "lake stretching to distant shore, trees or mountains across water, sky reflected in water"
  },

  waterfall: {
    indoorOutdoor: "outdoor",
    reflectiveSurfaces: "water spray creating mist, wet rocks reflecting light",
    exposureAdjustment: "bright flowing water needs careful exposure, may show slight motion blur",
    colorCast: "cool tones from water and mist, green from surrounding nature",
    specialLighting: "diffused light from mist, sparkle on water droplets, soft scattered light",
    atmosphericConditions: "misty humid atmosphere, fresh water spray visible in air",
    groundSurface: "wet rocks, natural stone, possibly wooden viewing platform",
    depthElements: "waterfall prominent in background, mist rising, rocks and vegetation, flowing water movement"
  },

  desert: {
    indoorOutdoor: "outdoor",
    reflectiveSurfaces: "minimal, matte sand, possible heat shimmer",
    exposureAdjustment: "very bright, intense sunlight, high contrast",
    colorCast: "warm golden-orange from sand, deep blue sky contrast",
    specialLighting: "harsh intense sunlight, sand acts as warm reflector, heat haze possible",
    atmosphericConditions: "dry clear air, possible heat distortion, warm environment",
    groundSurface: "sand dunes with wind texture, rocks, desert soil",
    depthElements: "layered sand dunes, desert plants, vast open sky, distant horizon with heat shimmer"
  },

  garden: {
    indoorOutdoor: "outdoor",
    reflectiveSurfaces: "minimal, soft natural surfaces, possibly wet foliage",
    exposureAdjustment: "pleasant balanced light, colorful flowers may need slight underexposure",
    colorCast: "vibrant greens and flower colors, natural organic tones",
    specialLighting: "soft natural light, possible dappled shade from plants, gentle shadows",
    atmosphericConditions: "fresh garden atmosphere, pleasant outdoor setting",
    groundSurface: "garden path - stone, gravel, or grass, manicured ground",
    depthElements: "flowers and plants surrounding, garden bed layers, foliage creating depth, pathway visible"
  },

  park: {
    indoorOutdoor: "outdoor",
    reflectiveSurfaces: "minimal, grass and natural surfaces",
    exposureAdjustment: "open area balanced exposure, shade under trees darker",
    colorCast: "green from grass and trees, natural outdoor tones",
    specialLighting: "open sky light or filtered through trees, natural shadows from foliage",
    atmosphericConditions: "fresh outdoor air, casual relaxed environment",
    groundSurface: "grass, dirt path, or paved park walkway",
    depthElements: "trees in background, other park visitors distant, open grass areas, park benches or features"
  },

  rooftop: {
    indoorOutdoor: "outdoor",
    reflectiveSurfaces: "glass railings, metal fixtures, possibly wet surfaces after rain",
    exposureAdjustment: "very open to sky, bright and airy, minimal shadows",
    colorCast: "urban skyline colors, cool modern tones",
    specialLighting: "open sky overhead, minimal obstruction, possibly wind-blown hair",
    atmosphericConditions: "elevated open air, urban environment, breezy",
    groundSurface: "rooftop decking, concrete, modern materials",
    depthElements: "city skyline behind, buildings at various distances, vast sky, rooftop features like planters or furniture"
  },

  bridge: {
    indoorOutdoor: "outdoor",
    reflectiveSurfaces: "water below reflecting light, metal or stone bridge surfaces",
    exposureAdjustment: "balanced, possible bright water reflections",
    colorCast: "cool tones from water and metal/stone, urban or natural depending on bridge",
    specialLighting: "open to sky, architectural shadows from bridge structure",
    atmosphericConditions: "airy open feeling, possibly breezy over water",
    groundSurface: "bridge walkway - concrete, wood planks, or metal grating",
    depthElements: "bridge cables or arches framing, water below visible through rails, cityscape or landscape beyond"
  },

  airport: {
    indoorOutdoor: "indoor",
    reflectiveSurfaces: "polished terminal floors, large glass windows, metallic surfaces",
    exposureAdjustment: "mixed natural window light and bright interior lighting",
    colorCast: "cool modern whites and grays, possibly warm from tungsten accents",
    specialLighting: "bright even fluorescent overhead, large windows providing natural side light",
    atmosphericConditions: "modern clean interior, air-conditioned, busy travel environment",
    groundSurface: "polished terminal flooring with subtle reflections",
    depthElements: "terminal architecture, large windows, other travelers blurred, flight boards, modern airport interior"
  },

  gym: {
    indoorOutdoor: "indoor",
    reflectiveSurfaces: "mirrors on walls, polished equipment, possibly sweaty skin sheen",
    exposureAdjustment: "bright fluorescent interior lighting, even exposure",
    colorCast: "cool whites and equipment colors, athletic environment",
    specialLighting: "bright overhead fluorescent, possible mirror reflections",
    atmosphericConditions: "interior athletic environment, air-conditioned",
    groundSurface: "gym flooring - rubber, wood, or mat",
    depthElements: "gym equipment in background, mirrors, other gym-goers blurred, weights and machines"
  },

  library: {
    indoorOutdoor: "indoor",
    reflectiveSurfaces: "polished wood surfaces, glass, quiet reflective surfaces",
    exposureAdjustment: "moderate interior lighting, warm reading lamps",
    colorCast: "warm from wood and books, soft academic tones",
    specialLighting: "soft reading lights, natural window light, even ambient interior",
    atmosphericConditions: "quiet studious interior, controlled climate",
    groundSurface: "library flooring - carpet, wood, or tile",
    depthElements: "bookshelves creating depth, reading areas, architectural details, rows of books"
  },

  museum: {
    indoorOutdoor: "indoor",
    reflectiveSurfaces: "polished floors, glass cases, gallery lighting reflections",
    exposureAdjustment: "carefully controlled gallery lighting, even exposure",
    colorCast: "neutral whites, professional gallery lighting temperature",
    specialLighting: "directional track lighting on art, soft diffused ambient light, professional museum illumination",
    atmosphericConditions: "quiet cultural interior, climate-controlled",
    groundSurface: "polished museum floor with subtle reflections",
    depthElements: "gallery walls with art, other visitors distant, spacious white or colored walls, exhibition layout"
  },

  restaurant: {
    indoorOutdoor: "indoor",
    reflectiveSurfaces: "polished table surfaces, glassware, cutlery reflections",
    exposureAdjustment: "dimmer ambient lighting, higher ISO needed",
    colorCast: "warm tungsten glow, romantic dim lighting tones",
    specialLighting: "spot lighting on tables, candles possible, warm intimate ambiance",
    atmosphericConditions: "cozy dining interior, warm social environment",
    groundSurface: "restaurant flooring, possibly carpet or hardwood",
    depthElements: "table settings, other diners blurred, restaurant decor, ambient dining atmosphere"
  },

  hotel_lobby: {
    indoorOutdoor: "indoor",
    reflectiveSurfaces: "marble floors, glass features, polished surfaces",
    exposureAdjustment: "bright elegant interior lighting, well-lit luxury space",
    colorCast: "sophisticated neutrals, warm accent lighting",
    specialLighting: "elegant chandelier lighting, ambient luxury illumination, architectural lighting",
    atmosphericConditions: "upscale interior, air-conditioned, sophisticated environment",
    groundSurface: "polished marble or luxury flooring with reflections",
    depthElements: "hotel architecture, lobby furniture, reception area, elegant spatial design"
  },

  pool: {
    indoorOutdoor: "outdoor",
    reflectiveSurfaces: "water surface reflecting sky and surroundings, wet deck surfaces",
    exposureAdjustment: "bright from water reflections, possible overexposure risk",
    colorCast: "blue from pool water, warm from deck and sun",
    specialLighting: "bright open sky, strong reflection from water creating fill light",
    atmosphericConditions: "vacation resort atmosphere, bright sunny environment",
    groundSurface: "pool deck - tile, concrete, or wood decking",
    depthElements: "pool water, lounge chairs, umbrellas, resort background, tropical plants possible"
  },

  yacht: {
    indoorOutdoor: "outdoor",
    reflectiveSurfaces: "water surrounding creating bright reflections, polished boat surfaces",
    exposureAdjustment: "very bright from water on all sides, natural fill light",
    colorCast: "blue from ocean and sky, white from boat, nautical colors",
    specialLighting: "open sky overhead, water reflections from all angles creating bright even light",
    atmosphericConditions: "maritime environment, breezy, open sea air",
    groundSurface: "yacht deck - teak wood or fiberglass",
    depthElements: "boat railings, ocean extending to horizon, boat features, distant coastline possible"
  },

  bookstore: {
    indoorOutdoor: "indoor",
    reflectiveSurfaces: "minimal, matte book covers and wood",
    exposureAdjustment: "cozy moderate interior lighting, warm reading environment",
    colorCast: "warm from wood and books, cozy intellectual tones",
    specialLighting: "soft ambient interior, reading lamps, warm inviting glow",
    atmosphericConditions: "quiet cozy interior, comfortable browsing environment",
    groundSurface: "bookstore flooring - wood or carpet",
    depthElements: "bookshelves creating aisles, stacked books, reading nooks, cozy bookstore atmosphere"
  },

  coffee_shop: {
    indoorOutdoor: "indoor",
    reflectiveSurfaces: "polished counter, coffee machines, glassware",
    exposureAdjustment: "mixed natural window light and warm interior lights",
    colorCast: "warm from interior lighting and wood tones, coffee shop ambiance",
    specialLighting: "pendant lights, large windows providing natural light, warm café glow",
    atmosphericConditions: "cozy social interior, coffee aroma atmosphere",
    groundSurface: "café flooring - tile, wood, or polished concrete",
    depthElements: "barista counter, coffee equipment, other customers blurred, café seating, pastry displays"
  },

  home_interior: {
    indoorOutdoor: "indoor",
    reflectiveSurfaces: "furniture surfaces, possible windows, home decor",
    exposureAdjustment: "typical home lighting - lamps and natural window light",
    colorCast: "warm from interior lighting, personal home tones",
    specialLighting: "mixed natural window light and warm interior lamps, cozy home illumination",
    atmosphericConditions: "comfortable personal space, lived-in atmosphere",
    groundSurface: "home flooring - carpet, hardwood, or tile",
    depthElements: "furniture arrangement, home decor, windows, personal living space details"
  },

  balcony: {
    indoorOutdoor: "outdoor",
    reflectiveSurfaces: "glass railing, potted plant containers, metal furniture",
    exposureAdjustment: "open to sky and view, balanced outdoor lighting",
    colorCast: "natural outdoor tones plus view colors",
    specialLighting: "open sky above, view providing ambient light from direction",
    atmosphericConditions: "semi-outdoor space, elevated view, breezy",
    groundSurface: "balcony flooring - tile, wood decking, or concrete",
    depthElements: "railing, potted plants, furniture, city or nature view beyond, outdoor living space"
  },

  cherry_blossoms: {
    indoorOutdoor: "outdoor",
    reflectiveSurfaces: "minimal, soft natural surfaces",
    exposureAdjustment: "delicate pink flowers may need slight underexposure to preserve detail",
    colorCast: "soft pink from blossoms, fresh spring greens",
    specialLighting: "filtered light through pink blossoms, soft romantic glow",
    atmosphericConditions: "fresh spring atmosphere, delicate natural beauty",
    groundSurface: "grass or path, possibly fallen petals scattered",
    depthElements: "cherry blossom branches framing, tree canopy, pink flowers surrounding, spring garden atmosphere"
  },

  autumn_leaves: {
    indoorOutdoor: "outdoor",
    reflectiveSurfaces: "minimal, matte fall foliage",
    exposureAdjustment: "vibrant colors need careful exposure, rich autumn tones",
    colorCast: "warm oranges, reds, yellows from fall foliage",
    specialLighting: "warm autumn light, filtered through colorful leaves",
    atmosphericConditions: "crisp fall air, autumn seasonal beauty",
    groundSurface: "ground covered with fallen leaves, autumn path",
    depthElements: "trees with colorful foliage, fallen leaves around, autumn forest or park depth"
  },

  snow_scene: {
    indoorOutdoor: "outdoor",
    reflectiveSurfaces: "highly reflective snow acting as giant white reflector, very bright",
    exposureAdjustment: "bright from snow reflection, careful not to underexpose subject",
    colorCast: "cool blue shadows on snow, bright white highlights, winter tones",
    specialLighting: "snow provides strong fill light from below, bright even illumination",
    atmosphericConditions: "cold crisp winter air, quiet snow-covered landscape",
    groundSurface: "snow-covered ground with texture and footprints",
    depthElements: "snow-covered landscape, winter trees, possibly falling snow, winter scenery depth"
  },

  rain: {
    indoorOutdoor: "outdoor",
    reflectiveSurfaces: "wet pavement reflecting lights and sky, puddles, raindrops",
    exposureAdjustment: "overcast diffused light, darker than sunny conditions",
    colorCast: "cool gray tones, desaturated colors, moody atmosphere",
    specialLighting: "soft diffused overcast light, reflections in wet surfaces, possible umbrella shade",
    atmosphericConditions: "rainy weather, wet atmosphere, visible rain possible",
    groundSurface: "wet pavement or ground with puddles, rain texture",
    depthElements: "rain visible in air, wet surfaces reflecting, overcast sky, moody rainy atmosphere"
  },

  graffiti_wall: {
    indoorOutdoor: "outdoor",
    reflectiveSurfaces: "possibly wet paint sheen, urban surfaces",
    exposureAdjustment: "varied depending on time, colorful wall may affect exposure",
    colorCast: "vibrant colors from graffiti art, urban tones",
    specialLighting: "urban ambient light, wall colors affecting color bounce",
    atmosphericConditions: "urban street environment, creative artistic setting",
    groundSurface: "urban pavement, street surface, possibly alley ground",
    depthElements: "colorful graffiti wall prominent behind, urban textures, street art details, creative urban setting"
  },

  neon_lights: {
    indoorOutdoor: "outdoor",
    reflectiveSurfaces: "wet pavement reflecting neon, glass storefronts",
    exposureAdjustment: "night scene with bright neon requiring careful exposure balance",
    colorCast: "vibrant mixed neon colors - pink, blue, purple, green",
    specialLighting: "colorful neon signs as primary light sources, dramatic colored illumination",
    atmosphericConditions: "nightlife atmosphere, urban evening energy, vibrant city night",
    groundSurface: "urban street pavement, possibly wet reflecting neon",
    depthElements: "neon signs glowing, storefronts, urban nightlife background, colorful light pollution"
  },

  vintage_car: {
    indoorOutdoor: "outdoor",
    reflectiveSurfaces: "classic car chrome and paint reflecting surroundings",
    exposureAdjustment: "careful balance for reflective car surfaces",
    colorCast: "vintage car colors, nostalgic retro tones",
    specialLighting: "car surfaces reflecting environment, specular highlights on chrome",
    atmosphericConditions: "nostalgic retro setting, classic automotive environment",
    groundSurface: "pavement, classic car show ground, or vintage street",
    depthElements: "vintage automobile prominent, retro details, classic car features, nostalgic background"
  },

  motorcycle: {
    indoorOutdoor: "outdoor",
    reflectiveSurfaces: "motorcycle metal and paint, chrome details",
    exposureAdjustment: "balanced for bike and surroundings",
    colorCast: "motorcycle colors, adventurous outdoor tones",
    specialLighting: "reflections on bike surfaces, outdoor lighting",
    atmosphericConditions: "adventurous outdoor or urban setting, open road feeling",
    groundSurface: "road pavement, parking area, or scenic overlook",
    depthElements: "motorcycle visible, open road or urban background, adventure atmosphere"
  },

  ferris_wheel: {
    indoorOutdoor: "outdoor",
    reflectiveSurfaces: "ferris wheel metal structure, possible carnival lights",
    exposureAdjustment: "bright if daytime, mixed lighting if evening with carnival lights",
    colorCast: "festive carnival colors, fun fair atmosphere",
    specialLighting: "carnival lights if evening, bright fair atmosphere, playful lighting",
    atmosphericConditions: "festive carnival or fair environment, fun recreational atmosphere",
    groundSurface: "fair grounds, carnival pavement",
    depthElements: "ferris wheel prominent in background, carnival attractions, festive fair atmosphere"
  },

  concert_venue: {
    indoorOutdoor: "indoor/outdoor",
    reflectiveSurfaces: "stage lights, crowd surfaces, venue architecture",
    exposureAdjustment: "mixed bright stage lights and darker crowd areas",
    colorCast: "colored stage lighting, concert atmosphere colors",
    specialLighting: "dramatic stage lighting, spotlights, concert illumination",
    atmosphericConditions: "energetic music venue atmosphere, crowd energy",
    groundSurface: "venue floor, concert ground",
    depthElements: "stage visible, crowd, concert lighting, energetic music venue atmosphere"
  },

  sports_stadium: {
    indoorOutdoor: "outdoor/indoor",
    reflectiveSurfaces: "stadium surfaces, seats, field",
    exposureAdjustment: "bright stadium lighting if indoor, natural if outdoor",
    colorCast: "team colors, stadium atmosphere tones",
    specialLighting: "bright stadium lights or natural daylight, even sports illumination",
    atmosphericConditions: "athletic event atmosphere, stadium energy",
    groundSurface: "stadium concourse or seating area",
    depthElements: "stadium architecture, field visible, seats, sports venue atmosphere"
  }
};

// ============================================================================
// SMART LIGHTING COMBINATION FUNCTION
// Intelligently combines time-based lighting with location-specific modifiers
// ============================================================================
function getCombinedLightingPrompt(sceneType, timeOfDay, shotType) {
  const lighting = lightingProfiles[timeOfDay] || lightingProfiles.sunset;
  const place = placeModifiers[sceneType] || placeModifiers.cafe;

  // Handle special combinations and edge cases
  let specialHandling = "";

  // Indoor locations during sunrise/sunset get window light treatment
  if (place.indoorOutdoor === "indoor" && (timeOfDay === "sunrise" || timeOfDay === "sunset")) {
    specialHandling = `Warm ${timeOfDay} light streaming through large windows, creating dramatic golden beams across interior. Interior lights may be dimmed or off, relying on natural window light. `;
  }

  // Indoor locations at night rely purely on artificial lighting
  if (place.indoorOutdoor === "indoor" && timeOfDay === "night") {
    specialHandling = `Interior artificial lighting only - warm tungsten or cool LED depending on venue type. No natural light. ${place.specialLighting}. `;
  }

  // Outdoor locations at night need artificial light sources
  if (place.indoorOutdoor === "outdoor" && timeOfDay === "night") {
    specialHandling = `Night scene with artificial lighting - street lights, building lights, or ambient city glow. ${lighting.specialNotes}. `;
  }

  // Beach/water/snow at noon needs special exposure handling
  if ((sceneType.includes('beach') || sceneType.includes('pool') || sceneType.includes('snow') || sceneType.includes('yacht')) && timeOfDay === "noon") {
    specialHandling = `Extremely bright conditions from ${place.reflectiveSurfaces}. Subject may be squinting. Very high key exposure. `;
  }

  // Build comprehensive lighting description
  const lightingPrompt = `
PHOTOGRAPHY TECHNICAL SPECS:
Camera: iPhone 15 Pro in standard photo mode
Time: ${timeOfDay}
ISO: ${lighting.iso} (${lighting.grainLevel})
${specialHandling}

LIGHTING ANALYSIS:
• Color Temperature: ${lighting.colorTemp}
• Light Direction: ${lighting.lightDirection}
• Shadow Character: ${lighting.shadowType}
• Contrast Level: ${lighting.contrast}
• Sky/Ambient: ${lighting.skyDescription}
• Exposure: ${lighting.exposure}

LOCATION-SPECIFIC LIGHTING:
• Environment: ${place.indoorOutdoor}
• Special Lighting: ${place.specialLighting}
• Reflective Surfaces: ${place.reflectiveSurfaces}
• Color Cast: ${place.colorCast}
• Atmospheric Conditions: ${place.atmosphericConditions}
• Exposure Adjustment: ${place.exposureAdjustment}

ENVIRONMENTAL DEPTH:
• Ground Surface: ${place.groundSurface}
• Depth Elements: ${place.depthElements}

PHOTOGRAPHY REALISM:
• ${lighting.specialNotes}
• Realistic phone camera depth of field - subject sharp, background naturally blurred based on distance
• Natural ${timeOfDay} color grading - NOT oversaturated
• Authentic iPhone ${lighting.iso} grain characteristics
• Real skin texture visible - pores and natural skin, NOT airbrushed
• Lighting on subject matches environment lighting perfectly
• Natural shadows and highlights based on light direction
• ${shotType} composition with natural casual framing`;

  return lightingPrompt;
}

// ============================================================================
// ENHANCED SCENE MAP with detailed visual descriptions
// ============================================================================
const sceneMap = {
  // ========== ORIGINAL CORE SCENES ==========
  cafe: "outdoor sidewalk café seating - small round marble-top table with metal bistro chair in foreground, other occupied café tables blurred in background, café storefront with awning visible behind, potted plants nearby, sidewalk pavement underneath, casual urban street café atmosphere with pedestrians passing in distance",

  mountain: "mountain overlook vista - standing on rocky outcrop viewpoint in foreground, scattered stones and mountain vegetation underfoot, multiple layered mountain peaks in background with atmospheric blue haze on distant ranges, pine or fir trees framing edges of frame, hiking trail visible leading away, vast open sky above, natural wilderness depth",

  beach: "sandy beach location - standing on textured sand beach in foreground with visible footprints, gentle ocean waves rolling in middle distance, wet sand and scattered seashells near shoreline, ocean extending to horizon line in background, scattered beach grass or driftwood adding natural elements, open sky above, natural beach debris and texture",

  luxury_car: "modern luxury automobile setting - sleek contemporary luxury car (Mercedes, BMW, Tesla style) parked on clean city street, person positioned near car door or leaning casually against vehicle, polished car paint reflecting environment, chrome details catching light, city buildings and urban architecture in background, smooth pavement underneath, upscale urban automotive atmosphere",

  city_street: "urban street scene - standing on wide city sidewalk with textured concrete pavement, storefronts with large display windows lining street behind, modern buildings creating urban canyon, pedestrians blurred walking past in background, street signs and urban furniture visible, possible parked cars along curb, typical metropolitan street atmosphere with depth from building perspective",

  // ========== NATURE & OUTDOOR SCENES ==========
  forest: "woodland forest trail - standing on natural dirt hiking path cutting through forest, fallen leaves and pine needles scattered on ground, tall tree trunks surrounding and framing composition, dappled sunlight filtering through dense tree canopy above creating light patches, ferns and undergrowth visible, forest extending into blurred green depth, natural woodland atmosphere with layered foliage",

  lake: "peaceful lakeside location - standing on natural shoreline with grass and smooth stones underfoot, calm lake water extending from foreground to middle distance, tree line visible across lake on far shore, lake surface reflecting sky and surroundings, possibly wooden dock or pier nearby, distant mountains or hills beyond lake, sky and clouds mirrored in still water, serene natural water landscape",

  waterfall: "scenic waterfall viewpoint - standing on wet rocks or wooden viewing platform near waterfall, cascading water visible in background with white flowing water, water spray and mist in air creating atmospheric effect, lush green vegetation and ferns surrounding, smooth water-worn rocks in foreground, rainbow possible in mist, sound of rushing water atmosphere, natural stone and plant depth",

  desert: "arid desert landscape - standing on textured sand with wind-blown ripple patterns underfoot, sand dunes rolling in background creating layers of depth, possibly scattered desert rocks or sparse vegetation, vast open desert extending to horizon, deep blue cloudless sky above, possible heat shimmer distortion in distance, warm sand tones and dramatic desert atmosphere",

  garden: "cultivated garden setting - standing on stone garden path or grass, colorful flower beds blooming on both sides, variety of plants and flowers creating natural frame, garden foliage in multiple layers providing depth, possibly garden arbor or trellis in background, manicured bushes and organized plantings, garden tools or decorative elements subtly visible, peaceful cultivated nature atmosphere",

  park: "public park environment - standing on grass or paved park pathway, mature trees providing natural canopy and shade, park bench visible nearby, other park visitors blurred in far background, open grass areas extending into distance, possibly playground or park features in background, natural parkland with walking paths visible, relaxed outdoor recreational atmosphere",

  sunset_field: "open meadow at golden hour - standing in wild grass field with tall grass and wildflowers in foreground, open field extending to horizon, dramatic sunset sky with warm orange and pink gradient, sun low on horizon creating silhouette or rim lighting, grass swaying suggesting gentle breeze, possibly distant tree line on horizon, magical golden hour atmosphere with warm glow everywhere",

  // ========== URBAN & ARCHITECTURE ==========
  rooftop: "rooftop terrace setting - standing on modern rooftop deck with composite or concrete flooring, glass or metal railing in foreground, city skyline with buildings at varying distances in background, rooftop furniture like lounge chairs or planters nearby, vast open sky above, possibly rooftop plants or greenery, elevated urban atmosphere with expansive city view and sense of height",

  bridge: "iconic bridge location - standing on bridge pedestrian walkway with distinctive bridge architecture visible (cables, arches, or suspension elements), bridge railing in foreground, water or valley visible below through railing, cityscape or landscape extending beyond bridge, bridge structure creating strong architectural framing, pedestrian path underneath, sense of crossing and connection, architectural landmark atmosphere",

  shopping_district: "busy shopping street - standing on commercial street with luxury or trendy storefronts flanking both sides, large display windows showing merchandise, stylish shop facades and brand signage, pedestrian shopping traffic blurred in background, polished sidewalk or pedestrian zone pavement, street furniture and planters, vibrant retail atmosphere with commercial energy and urban shopping district depth",

  metro_station: "modern subway station - standing on wide metro platform with platform edge line visible, architectural ceiling with modern lighting fixtures above, metro map and signage on walls, tracks visible at platform edge, other commuters waiting blurred in distance, polished tile or concrete flooring, contemporary transit architecture with clean lines, urban public transportation atmosphere",

  skyscraper: "downtown skyscraper plaza - standing in front of modern glass and steel skyscrapers, building facades with reflective glass windows soaring upward, urban plaza paving stones or concrete underfoot, possibly corporate sculpture or plaza features, other tall buildings creating urban canyon, people in business attire blurred in background, downtown metropolitan atmosphere with towering architecture and business district energy",

  alley: "charming urban alley - standing in narrow pedestrian alley between buildings, interesting textured brick or painted walls on both sides, possibly colorful street art or murals, alley extending into depth with perspective, hanging plants or café tables creating intimate atmosphere, cobblestone or brick pavement underfoot, urban character with narrow intimate space, possibly string lights overhead",

  plaza: "public urban plaza - standing in open public square with expansive paved area, plaza paving in geometric patterns, surrounding buildings creating plaza perimeter, public art or fountain visible, pedestrians crossing plaza in various directions blurred, plaza benches and urban furniture, open sky above, civic architecture visible, bustling public gathering space atmosphere",

  // ========== LANDMARKS & TRAVEL ==========
  eiffel_tower: "Eiffel Tower Paris location - standing on Trocadéro plaza or Champ de Mars with Parisian pavement underfoot, iconic Eiffel Tower metal structure prominent in background, manicured French gardens or plaza visible, typical Paris architecture surrounding, tourists blurred in distance, classic Parisian lampposts or fountains, world-famous landmark atmosphere with unmistakable iron lattice tower",

  times_square: "Times Square New York - standing in pedestrian zone of Times Square with distinctive red TKTS stairs nearby, massive illuminated billboards and digital screens towering on all sides, bright advertising creating colorful light pollution, yellow taxis and city traffic blurred in background, crowds of tourists surrounding, distinctive NYC energy and sensory overload, iconic American commercial intersection atmosphere",

  colosseum: "Colosseum Rome setting - standing near ancient Roman Colosseum with weathered travertine stone arches visible, archaeological ruins and Roman architecture in background, old Roman stone pavement or modern plaza underneath, tourists at historic site blurred in distance, ancient Roman columns and archways, Mediterranean light on ancient stone, world heritage historical atmosphere",

  taj_mahal: "Taj Mahal India location - standing in Taj Mahal gardens with ornamental pathway and reflecting pools, iconic white marble mausoleum with distinctive dome and minarets in background, Mughal garden landscaping with cypress trees, marble inlay pathways underfoot, tourists visiting monument in distance, Indian architectural masterpiece atmosphere with symmetrical Islamic design",

  statue_liberty: "Statue of Liberty New York - standing on Liberty Island or ferry with view of statue, iconic copper statue with torch and crown visible in background, New York harbor water and Manhattan skyline in distance, ferry railing or island walkway in foreground, American flag possibly visible, harbor boats and activity, patriotic American landmark atmosphere",

  big_ben: "Big Ben London scene - standing in Westminster area with view of Elizabeth Tower (Big Ben) and Parliament, Gothic Revival architecture of Parliament buildings, London street or Westminster Bridge pavement underfoot, River Thames possibly visible, red London buses or black cabs blurred passing, classic British landmark atmosphere with Victorian Gothic architecture",

  // ========== LEISURE & ACTIVITIES ==========
  airport: "airport terminal interior - standing in spacious modern terminal with polished reflective floor, floor-to-ceiling windows providing natural light in background, flight information displays visible on walls, other travelers with luggage blurred walking past, terminal seating areas and gates in distance, high ceilings with contemporary architecture, modern aviation travel atmosphere with sense of journey and departure",

  gym: "fitness gym interior - standing in workout area with modern gym equipment visible in background (treadmills, weight machines, racks), large wall mirrors reflecting space, rubber or wood gym flooring underfoot, other gym members exercising blurred in background, bright fluorescent overhead lighting, athletic motivation posters or gym branding, energetic fitness atmosphere with workout equipment depth",

  library: "beautiful library interior - standing between library bookshelves or in reading area, floor-to-ceiling wooden bookshelves filled with books creating vertical lines, comfortable reading chairs and tables visible, warm reading lamps providing ambient glow, other library visitors quietly reading blurred in background, hardwood or carpet library flooring, high ceilings with architectural details, quiet intellectual atmosphere",

  museum: "art museum gallery - standing in white-walled gallery space with polished museum floor, framed artwork hanging on walls at various distances, gallery track lighting illuminating art, other museum visitors admiring art blurred in background, museum benches for viewing, high ceilings with professional lighting, quiet cultural atmosphere with artistic exhibition layout and gallery depth",

  restaurant: "upscale restaurant interior - standing near dining table with elegant place settings visible (wine glasses, silverware, white tablecloth), other occupied tables with diners blurred in background, ambient warm pendant or chandelier lighting above, restaurant decor and wall art, hardwood or carpet flooring, waitstaff possibly visible in distance, sophisticated dining atmosphere with romantic or upscale ambiance",

  hotel_lobby: "luxury hotel lobby - standing in grand hotel entrance with polished marble flooring reflecting lights, elegant chandelier or modern lighting fixtures above, upscale furniture groupings (sofas, armchairs), hotel reception desk visible in background, large floral arrangements, other hotel guests blurred in background, high ceilings with architectural grandeur, sophisticated hospitality atmosphere",

  pool: "resort swimming pool - standing on pool deck with textured non-slip tile or wood decking, crystal blue pool water visible with reflections, white or colorful lounge chairs lined up, poolside umbrellas providing shade, tropical plants or palm trees in planters, other resort guests relaxed by pool blurred, hotel building in background, vacation resort atmosphere with leisure and relaxation",

  yacht: "luxury yacht deck - standing on polished teak or fiberglass yacht deck, boat railing with metal or rope details in foreground, open ocean or coastal water extending to horizon, yacht sailing equipment (masts, rigging) visible, other boat features like seating or cockpit, distant coastline or other boats, maritime flags, ocean spray or wake, nautical luxury atmosphere with sea and sky",

  // ========== COZY & INDOOR ==========
  bookstore: "independent bookstore interior - standing in bookstore aisle between tall wooden bookshelves packed with books, colorful book spines creating visual texture, cozy reading nook with armchair visible in background, vintage library ladder leaning against shelves, warm ambient lighting from reading lamps, other bookstore browsers blurred, hardwood creaky flooring, stacks of featured books on display tables, literary cozy atmosphere",

  coffee_shop: "hip coffee shop interior - standing near café counter or seating area with specialty coffee equipment (espresso machine, grinders) visible behind counter, blackboard menu with chalk writing, pendant Edison bulb lighting overhead, wooden tables and chairs, other café customers working on laptops blurred, coffee cups and pastries in glass display case, barista preparing drinks, warm café atmosphere with coffee culture vibe",

  home_interior: "stylish home living room - standing in modern or cozy home interior with comfortable sofa and furniture, decorative elements like artwork or plants, natural light from large windows, home accessories and personal items, area rug on floor, possibly fireplace or TV area, cozy throw blankets or pillows, lived-in but styled home atmosphere with personal touches and comfortable residential space",

  balcony: "private apartment balcony - standing on balcony with flooring (tile, wood decking, or concrete), metal or glass railing in foreground, potted plants and small balcony garden, outdoor balcony furniture (small table and chairs), view beyond railing showing city buildings or nature, balcony string lights or lanterns, vertical space with plants climbing, semi-outdoor living space atmosphere",

  // ========== SEASONAL & SPECIAL ==========
  cherry_blossoms: "cherry blossom grove - standing under blooming cherry blossom trees with pink flower canopy above, fallen cherry blossom petals scattered on ground and path, grass or park pathway underfoot, multiple cherry trees in background creating pink tunnel effect, soft pink light filtering through blossoms, possibly park visitors having hanami picnics blurred in background, spring magical atmosphere with delicate pink flowers everywhere",

  autumn_leaves: "autumn forest scene - standing on leaf-covered path through deciduous forest, ground blanketed with vibrant orange, red, and yellow fallen leaves, trees with colorful fall foliage creating canopy above, some leaves mid-fall floating in air, layered forest depth with autumn colors, crisp fall atmosphere with golden and rust tones, natural autumn beauty and seasonal transformation",

  snow_scene: "winter wonderland landscape - standing in snow-covered landscape with fresh snow on ground showing footprint trail, snow-laden evergreen trees or winter-bare deciduous trees, pristine white snow creating bright reflective surface, possibly gentle snowfall with visible flakes, distant snow-covered hills or mountains, winter sky (gray overcast or bright blue), cold crisp winter atmosphere with peaceful snowy scenery",

  rain: "rainy street scene - standing on wet pavement with visible puddles reflecting surroundings and lights, rain falling creating streaks in air, person possibly holding umbrella, wet surfaces creating mirror-like reflections, overcast gray sky, rain-soaked urban or park environment, blurred background through rain, water droplets visible on surfaces, moody atmospheric rainy day with diffused overcast lighting",

  // ========== UNIQUE & CREATIVE ==========
  graffiti_wall: "urban graffiti wall - standing in front of large colorful street art mural wall, vibrant spray paint artwork with detailed graffiti pieces, urban alley or street setting, concrete or brick wall covered in layered street art, possibly graffiti artist tags and murals, urban pavement or alley ground, gritty city textures, creative urban atmosphere with bold colors and street art culture",

  neon_lights: "neon-lit street scene - standing on urban street at night with vibrant neon signs glowing on storefronts and buildings, pink, blue, purple, and green neon light reflecting on wet pavement, Asian-inspired signage or retro Americana neon, electric glow creating colorful atmosphere, city nightlife setting, possibly rain-wet streets enhancing neon reflections, cyberpunk or retro nightlife atmosphere",

  vintage_car: "classic car setting - standing beside or leaning on beautifully restored vintage automobile (1950s-70s era), classic car with chrome bumpers and period-correct details, polished vintage paint finish, retro car show environment or nostalgic street setting, classic car features like whitewall tires or distinctive grille, pavement underneath, nostalgic retro atmosphere with automotive history charm",

  motorcycle: "motorcycle adventure scene - standing with motorcycle (cruiser, sport bike, or adventure bike style), bike positioned showing distinctive profile and details, open road or scenic overlook setting, motorcycle chrome and paint reflecting light, road or parking area underneath, possibly riding gear visible, landscape or urban backdrop suggesting journey, freedom and adventure atmosphere with motorcycle culture vibe",

  ferris_wheel: "amusement park ferris wheel - standing at carnival or pier with large colorful ferris wheel prominent in background, carnival rides and attractions visible, festive lights and fair atmosphere, paved carnival grounds or boardwalk underneath, other fair-goers enjoying attractions blurred, cotton candy or carnival food stands, festive fun atmosphere with recreational entertainment and joy",

  concert_venue: "live music concert - standing in concert crowd or near stage with stage lighting visible, concert lights creating dramatic colored beams (purple, blue, red), other concert attendees with hands up blurred around, stage and performers visible in background, venue floor or standing area, dramatic concert lighting and energy, live music atmosphere with festival or concert hall setting",

  sports_stadium: "sports stadium seating - standing in stadium with tiered seating rows visible, sports field or court in background, stadium lights illuminating venue, other fans in team colors blurred in seats, stadium architecture and scoreboards, concrete stadium steps or aisles, team banners and stadium branding, athletic event atmosphere with sports venue energy and fan excitement"
};

// ============================================================================
// MAIN CLOUD FUNCTION
// ============================================================================
exports.generateTravelPhoto = functions
  .runWith({
    timeoutSeconds: 540,
    memory: '1GB'
  })
  .firestore
  .document("users/{userId}/photos/{photoId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const { userId, photoId } = context.params;

    if (data.status !== "pending") return;

    try {
      console.log(`🔄 Processing photo ${photoId} for user ${userId}`);

      const bucket = admin.storage().bucket();
      let referenceImageBase64;

      // STEP 1: Get original image
      if (data.originalPath) {
        console.log(`📸 Downloading original image from path: ${data.originalPath}`);
        const [fileBuffer] = await bucket.file(data.originalPath).download();
        referenceImageBase64 = fileBuffer.toString('base64');
      } else if (data.originalUrl) {
        console.log("📸 Fetching original image from URL...");
        referenceImageBase64 = await imageUrlToBase64(data.originalUrl);
      } else {
        throw new Error("No originalPath or originalUrl found in document");
      }

      // STEP 2: Analyze person with improved prompt
      console.log("👁️  Analyzing person with Gemini...");
      const genAI = new GoogleGenerativeAI(GEN_AI_KEY);
      const analyzeModel = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });

      const analysisPrompt = `Analyze this person with precision for photorealistic recreation in a travel photo:

REQUIRED DETAILS:
- Facial structure: shape, distinctive features, expressions
- Hair: exact color (be specific), length, style, texture, natural or styled
- Skin: precise tone description (be specific with undertones), texture, any notable features
- Build: body type, height impression, posture
- Clothing: style (casual/formal), colors, fit, distinctive pieces
- Age appearance: approximate age range
- Notable characteristics: glasses, jewelry, facial hair, makeup style, etc.

Provide 2-3 descriptive phrases capturing distinctive identifying features that ensure this exact person is recognizable.

Example outputs:
"young woman in her 20s with shoulder-length wavy dark brown hair, warm medium skin tone with olive undertones, wearing casual denim jacket and white t-shirt"
"middle-aged man in his 40s with short salt-and-pepper hair and trimmed beard, fair skin, wearing business casual button-down shirt"`;

      const analysisResult = await analyzeModel.generateContent([
        { inlineData: { mimeType: "image/jpeg", data: referenceImageBase64 } },
        { text: analysisPrompt }
      ]);

      const analysisResponse = await analysisResult.response;
      if (!analysisResponse.candidates || analysisResponse.candidates.length === 0) {
        throw new Error("Gemini analysis returned no candidates");
      }

      const personDescription = await analysisResponse.text();
      console.log("✅ Person description:", personDescription);

      // STEP 3: Read user preferences
      const sceneType = data.sceneType || "cafe";
      const shotType = data.shotType || "fullbody";
      const timeOfDay = data.timeOfDay || "sunset";

      console.log("📍 User preferences:", { sceneType, shotType, timeOfDay });
      console.log(`🎨 Using lighting profile: ${timeOfDay} + ${sceneType}`);

      const sceneDescription = sceneMap[sceneType] || sceneMap.cafe;

      const shotPhraseMap = {
        fullbody: "Full-body shot showing entire figure from head to feet",
        half: "Half-body portrait from waist up showing upper body and face",
        closeup: "Close-up portrait with face and shoulders filling most of frame",
        landscape: "Wide landscape shot showing person as part of larger scene with extensive background",
      };

      const shotPhrase = shotPhraseMap[shotType] || shotPhraseMap.fullbody;

      // STEP 4: Get intelligent lighting combination
      const lightingInstructions = getCombinedLightingPrompt(sceneType, timeOfDay, shotType);

      // STEP 5: Build final ultra-realistic prompt
      const generatePrompt = `Create an authentic iPhone 15 Pro photo of ${personDescription}.

SCENE DESCRIPTION:
${sceneDescription}

CAMERA COMPOSITION:
${shotPhrase}. Natural relaxed pose, candid moment as if photographed by a friend. Person appears comfortable and genuinely present in the environment.

${lightingInstructions}

CRITICAL SUBJECT MATCHING:
The person MUST be IDENTICAL to the reference image provided:
- Exact same facial features, structure, and expressions
- Same hair color, style, length, and texture
- Same skin tone with accurate complexion
- Same body type and build
- Same distinctive characteristics
- Person should be immediately recognizable as the same individual from reference

PHONE CAMERA AUTHENTICITY:
- Authentic iPhone 15 Pro image quality and characteristics
- Natural phone camera perspective and depth of field
- Realistic JPEG compression artifacts
- Natural color science of iPhone camera (accurate colors, not oversaturated)
- Appropriate ISO noise characteristics as specified above
- Authentic bokeh and focus characteristics of phone camera
- Slight imperfections expected in casual phone photography
- Natural lens distortion if wide angle

REALISM REQUIREMENTS:
- Person seamlessly integrated into environment with correct scale and proportions
- Lighting on subject perfectly matches environmental lighting conditions
- Shadows cast appropriately based on light direction
- Natural skin texture with visible pores and realistic skin (NOT smoothed/airbrushed)
- Realistic fabric textures on clothing
- Natural interaction with ground/surfaces (contact shadows, realistic positioning)
- Background elements properly blurred based on phone camera depth of field
- Cohesive color palette between subject and environment
- Environmental reflections and lighting interactions as appropriate
- Realistic atmospheric perspective and depth cues

STRICTLY FORBIDDEN:
- Studio lighting or professional portrait lighting setup
- Airbrushed or smoothed skin (must show real skin texture)
- Oversaturated or artificially enhanced colors
- Perfect professional model posing (must be casual and natural)
- HDR over-processing or tone-mapping artifacts
- "AI art" aesthetic or stylized rendering
- Duplicate people or multiple versions of subject
- Flat unrealistic lighting that doesn't match environment
- Artistic filters, vintage effects, or heavy post-processing
- Adding people who aren't in the reference image
- Changing the person's appearance, features, or identity

OUTPUT REQUIREMENT:
A believable, authentic travel photo that looks like it was taken on someone's iPhone 15 Pro and could be found in their Camera Roll. The kind of photo someone would proudly show friends saying "look where I was!" - casual, real, and natural.`;

      console.log("🍌 Generating 4 variants with Nano Banana (Gemini 2.5 Flash Image)...");

      // STEP 6: Generate with Vertex AI
      const projectId = process.env.GCLOUD_PROJECT || "photo-ai-16051";
      const location = "us-central1";

      const vertexClient = new GoogleGenAI({
        vertexai: true,
        project: projectId,
        location: location,
      });

      const variantCount = 4;

      // Initialize progress tracking
      await snap.ref.update({
        status: "generating",
        variantsCompleted: 0,
        variantsTotal: variantCount,
        generatedPaths: [], // Clear any previous paths
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(`🎬 Starting generation of ${variantCount} variants with progressive updates`);

      let successfulVariants = 0;

      for (let i = 0; i < variantCount; i++) {
        console.log(`✨ Generating variant ${i + 1}/${variantCount}...`);

        if (i > 0) {
          const delayMs = 7000;
          console.log(`⏳ Waiting ${delayMs}ms before next request...`);
          await sleep(delayMs);
        }

        const imageBase64Data = await retryWithBackoff(async () => {
          const response = await vertexClient.models.generateContent({
            model: 'gemini-2.5-flash-image',
            contents: [
              {
                text: generatePrompt
              },
              {
                inlineData: {
                  mimeType: "image/jpeg",
                  data: referenceImageBase64
                }
              }
            ],
            config: {
              responseModalities: [Modality.TEXT, Modality.IMAGE],
            }
          });

          for (const candidate of (response.candidates || [])) {
            if (candidate.content && candidate.content.parts) {
              for (const part of candidate.content.parts) {
                if (part.inlineData && part.inlineData.data) {
                  return part.inlineData.data;
                }
              }
            }
          }
          return null;
        });

        if (!imageBase64Data) {
          console.log(`⚠️  Variant ${i + 1} has no image data, skipping`);
          continue;
        }

        const imageBuffer = Buffer.from(imageBase64Data, 'base64');
        const fileName = `generated/${userId}/${photoId}_variant_${i + 1}.png`;
        const file = bucket.file(fileName);

        console.log(`📤 Uploading variant ${i + 1}/${variantCount}...`);
        await file.save(imageBuffer, { metadata: { contentType: "image/png" } });
        successfulVariants++;

        // PROGRESSIVE UPDATE: Save this variant to Firestore immediately
        const isLastVariant = (i + 1) === variantCount;
        await snap.ref.update({
          generatedPaths: admin.firestore.FieldValue.arrayUnion(fileName),
          variantsCompleted: i + 1,
          status: isLastVariant ? "completed" : "generating",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`✅ Variant ${i + 1} uploaded to ${fileName} and pushed to Firestore`);
        console.log(`📊 Progress: ${i + 1}/${variantCount} variants completed`);
      }

      if (successfulVariants === 0) {
        throw new Error("No valid images were generated");
      }

      // STEP 7: Final update with metadata
      await snap.ref.update({
        personDescription,
        sceneType: sceneType,
        shotType: shotType,
        timeOfDay: timeOfDay,
        fullPrompt: generatePrompt,
        lightingProfile: timeOfDay,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`🎉 SUCCESS: Generated ${generatedPaths.length} variants with intelligent lighting system`);
      console.log(`📊 Used: ${timeOfDay} lighting + ${sceneType} location modifiers`);

    } catch (error) {
      console.error("❌ ERROR:", error.message);

      await snap.ref.update({
        status: "failed",
        error: error.message,
      });
    }
  });
