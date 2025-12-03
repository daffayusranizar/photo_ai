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

      // STEP 2: Analyze person appearance with Gemini (optional but helpful)
      console.log("👁️  Analyzing person with Gemini...");
      const genAI = new GoogleGenerativeAI(GEN_AI_KEY);
      const analyzeModel = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });

      const analysisPrompt = `Analyze this selfie and provide a brief, clear description of the person in 1-2 sentences. Focus on: gender, approximate age, hair (color and style), and any distinctive features. Keep it concise for AI image generation.`;

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
      const timeOfDay = data.timeOfDay || "golden hour";

      console.log("📍 User preferences:", { place, shotType, timeOfDay });

      // Map shot types and times to prompt phrases
      const shotTypeMap = {
        'fullbody': 'full body shot of',
        'half': 'half body portrait of',
        'closeup': 'close-up portrait of',
        'landscape': 'wide landscape shot featuring'
      };

      const timeMap = {
        'morning': 'in soft morning light',
        'sunrise': 'during golden hour sunrise with warm tones',
        'noon': 'in bright midday light',
        'afternoon': 'in pleasant afternoon light',
        'sunset': 'during golden hour sunset with warm glow',
        'night': 'at night with dramatic lighting'
      };

      // STEP 4: Generate 4 images using Imagen 3 Customization API
      console.log("🖼️  Generating 4 variants with Imagen 3 Customization...");

      const { GoogleAuth } = require('google-auth-library');
      const auth = new GoogleAuth({
        scopes: 'https://www.googleapis.com/auth/cloud-platform'
      });
      const client = await auth.getClient();
      const projectId = await auth.getProjectId();
      const accessToken = await client.getAccessToken();

      // Build prompt using user preferences
      const shotPhrase = shotTypeMap[shotType] || shotTypeMap['fullbody'];
      const timePhrase = timeMap[timeOfDay] || timeMap['sunset'];

      const generatePrompt = `Create a photorealistic travel photograph: ${shotPhrase} a person[1] at ${place} ${timePhrase}. Professional travel photography, natural lighting, vibrant colors, high quality. The person should be the main subject and naturally integrated into the scene.`;

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

      // STEP 5: Upload all 4 variant images to Storage
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

      // STEP 6: Update Firestore with all variant URLs
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
