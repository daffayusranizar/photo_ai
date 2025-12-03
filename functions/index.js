const functions = require("firebase-functions");
const admin = require("firebase-admin");
const { GoogleGenerativeAI } = require("@google/generative-ai");

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

exports.generateTravelPhoto = functions.firestore
  .document("users/{userId}/photos/{photoId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const { userId, photoId } = context.params;

    if (data.status !== "pending") return;

    try {
      console.log(`🔄 Processing photo ${photoId} for user ${userId}`);

      const imageUrl = data.originalUrl;
      if (!imageUrl) {
        throw new Error("No originalUrl found in document");
      }

      // STEP 1: Convert original image to base64 for reference
      console.log("📸 Converting reference image...");
      const referenceImageBase64 = await imageUrlToBase64(imageUrl);

      // STEP 2: Analyze person appearance with Gemini (improved prompt)
      console.log("👁️  Analyzing person with Gemini...");
      const genAI = new GoogleGenerativeAI(GEN_AI_KEY);
      const analyzeModel = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });

      const analysisPrompt = `Describe this person briefly for use as SUBJECT_DESCRIPTION in an image generation model.
1-2 short phrases only, no verbs or full sentences.
Include: gender expression, approximate age, hair color and style, skin tone, and notable facial features or clothing.
Example format: "young woman with long dark hair and olive skin tone" or "middle-aged man with short grey hair and beard"`;

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

      // STEP 3: Read user preferences from document
      const place = data.place || "a beautiful scenic location";
      const shotType = data.shotType || "fullbody";
      const timeOfDay = data.timeOfDay || "sunset";

      console.log("📍 User preferences:", { place, shotType, timeOfDay });

      // IMPROVED: More detailed mapping for shot types
      const shotPhraseMap = {
        'fullbody': 'full-body travel photo of [1], complete figure visible from head to feet, person centered in composition',
        'half': 'half-body portrait of [1], captured from waist up, upper body and face clearly visible',
        'closeup': 'close-up portrait of [1], face and shoulders filling most of the frame, detailed facial features',
        'landscape': 'wide landscape scenic shot prominently featuring [1] as the main subject in the environment'
      };

      // IMPROVED: More specific time/lighting descriptions
      const timePhraseMap = {
        'morning': 'in soft morning light with clear sky, gentle warm tones, fresh atmosphere',
        'sunrise': 'during sunrise golden hour with warm low-angle sunlight, soft sky gradients from orange to blue, magical atmosphere',
        'noon': 'in bright midday sunlight, clear visibility, vibrant colors',
        'afternoon': 'in pleasant afternoon daylight, soft natural lighting, comfortable atmosphere',
        'sunset': 'during sunset golden hour with warm amber glow, colorful sky with orange and pink hues, romantic lighting',
        'night': 'at night with realistic artificial lighting, visible ambient lights, evening atmosphere with depth'
      };

      const shotPhrase = shotPhraseMap[shotType] || shotPhraseMap['fullbody'];
      const timePhrase = timePhraseMap[timeOfDay] || timePhraseMap['sunset'];

      // STEP 4: Build improved prompt with better structure
      const generatePrompt = `Create a highly realistic professional travel photograph of ${personDescription} [1].

Camera composition: ${shotPhrase}, natural relaxed pose, authentic candid travel moment.

Location: ${place}, clearly recognizable as a real-world destination, with visible environmental details and context.

Lighting and time: ${timePhrase}.

Photography style: high-quality travel photography, realistic natural colors and accurate skin tones, sharp focus on the person, natural background with appropriate depth of field, photorealistic details, no image distortion or artifacts, single person only - no duplicates or extra people resembling [1].

The person [1] should be the clear main subject, naturally integrated into the scene, looking comfortable and genuine as a traveler.`;

      console.log("🖼️  Generating 4 variants with Imagen 3 Customization...");

      // STEP 5: Call Imagen 3 Customization API
      const { GoogleAuth } = require('google-auth-library');
      const auth = new GoogleAuth({
        scopes: 'https://www.googleapis.com/auth/cloud-platform'
      });
      const client = await auth.getClient();
      const projectId = await auth.getProjectId();
      const accessToken = await client.getAccessToken();

      console.log("Calling Imagen 3 Customization API...");
      const fetch = (await import('node-fetch')).default;

      const imagenResponse = await fetch(
        `https://us-central1-aiplatform.googleapis.com/v1/projects/${projectId}/locations/us-central1/publishers/google/models/imagen-3.0-capability-001:predict`,
        {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${accessToken.token}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            instances: [{
              prompt: generatePrompt,
              referenceImages: [{
                referenceType: "REFERENCE_TYPE_SUBJECT",
                referenceId: 1,
                referenceImage: {
                  bytesBase64Encoded: referenceImageBase64
                },
                subjectImageConfig: {
                  subjectDescription: personDescription,
                  subjectType: "SUBJECT_TYPE_PERSON"
                }
              }]
            }],
            parameters: {
              sampleCount: 4,  // Generate 4 variants
              language: "en"
            }
          })
        }
      );

      if (!imagenResponse.ok) {
        const errorText = await imagenResponse.text();
        throw new Error(`Imagen Customization API error: ${imagenResponse.status} - ${errorText}`);
      }

      const imagenData = await imagenResponse.json();

      if (!imagenData.predictions || imagenData.predictions.length === 0) {
        throw new Error("Imagen returned no predictions");
      }

      console.log(`✅ Generated ${imagenData.predictions.length} variants`);

      // STEP 6: Upload all 4 variant images to Storage
      const bucket = admin.storage().bucket();
      const generatedUrls = [];

      for (let i = 0; i < imagenData.predictions.length; i++) {
        const prediction = imagenData.predictions[i];
        const imageBase64Data = prediction.bytesBase64Encoded;

        if (!imageBase64Data) {
          console.log(`⚠️  Variant ${i + 1} has no image data, skipping`);
          continue;
        }

        const imageBuffer = Buffer.from(imageBase64Data, 'base64');
        const fileName = `generated/${userId}/${photoId}_variant_${i + 1}.png`;
        const file = bucket.file(fileName);

        console.log(`📤 Uploading variant ${i + 1}/${imagenData.predictions.length}...`);
        await file.save(imageBuffer, { metadata: { contentType: "image/png" } });
        await file.makePublic();

        const publicUrl = `https://storage.googleapis.com/${bucket.name}/${fileName}`;
        generatedUrls.push(publicUrl);
        console.log(`✅ Variant ${i + 1} uploaded (${imageBuffer.length} bytes)`);
      }

      if (generatedUrls.length === 0) {
        throw new Error("No valid images were generated");
      }

      // STEP 7: Update Firestore with all variant URLs
      await snap.ref.update({
        status: "completed",
        generatedUrls: generatedUrls,
        personDescription,
        place: place,
        shotType: shotType,
        timeOfDay: timeOfDay,
        fullPrompt: generatePrompt,
        originalImageUrl: imageUrl,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`🎉 SUCCESS: Generated ${generatedUrls.length} variants`);
      console.log("URLs:", generatedUrls);

    } catch (error) {
      console.error("❌ ERROR:", error.message);

      await snap.ref.update({
        status: "failed",
        error: error.message,
      });
    }
  });
