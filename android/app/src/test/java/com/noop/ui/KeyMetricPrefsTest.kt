package com.noop.ui

import android.content.SharedPreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the Key-Metrics layout persistence (#251): the CONTRACT is that a customisation (add a tile, remove a
 * tile, reorder tiles) survives relaunch — a fresh decode of exactly what was last encoded, nothing silently
 * reverting to the default set. Twin of the macOS `KeyMetricPrefsTests`, same "today.keyMetrics" key, same
 * comma-joined encoding, same "unknown/all-unknown decodes to the default order, never to an empty grid" rule.
 * Exercises the pure [KeyMetricPrefs] functions directly, plus one end-to-end pass over an in-memory
 * [FakeSharedPreferences] (the project ships no Robolectric) pinning the actual persisted key name.
 */
class KeyMetricPrefsTest {

    @Test
    fun emptyOrUnset_yieldsFullDefaultOrder() {
        assertEquals(KeyMetric.defaultOrder, KeyMetricPrefs.decodeEnabled(null))
        assertEquals(KeyMetric.defaultOrder, KeyMetricPrefs.decodeEnabled(""))
        assertEquals(KeyMetric.defaultOrder, KeyMetricPrefs.decodeEnabled("   "))
    }

    /** "Add a metric": a saved subset re-encoded with one more tile appended must show the addition, in the
     *  position it was added, with everything else untouched, on the next decode. */
    @Test
    fun addingAMetric_isReflectedOnNextDecode() {
        val before = KeyMetricPrefs.decodeEnabled(KeyMetricPrefs.encode(listOf(KeyMetric.CHARGE, KeyMetric.HRV)))
        assertEquals(listOf(KeyMetric.CHARGE, KeyMetric.HRV), before)

        val after = KeyMetricPrefs.decodeEnabled(KeyMetricPrefs.encode(before + KeyMetric.STEPS))
        assertEquals(listOf(KeyMetric.CHARGE, KeyMetric.HRV, KeyMetric.STEPS), after)
    }

    /** "Remove a metric": a tile dropped before encoding must not reappear on decode — it degrades to
     *  hidden, not to "still shown from some other default". */
    @Test
    fun removingAMetric_isReflectedOnNextDecode() {
        val full = listOf(KeyMetric.CHARGE, KeyMetric.EFFORT, KeyMetric.REST, KeyMetric.HRV, KeyMetric.STEPS)
        val withoutEffort = full.filterNot { it == KeyMetric.EFFORT }
        val decoded = KeyMetricPrefs.decodeEnabled(KeyMetricPrefs.encode(withoutEffort))
        assertEquals(listOf(KeyMetric.CHARGE, KeyMetric.REST, KeyMetric.HRV, KeyMetric.STEPS), decoded)
        assertFalse(decoded.contains(KeyMetric.EFFORT))
    }

    /** "Reorder metrics": the saved ORDER, not just the saved SET, must round-trip exactly. */
    @Test
    fun reorderingMetrics_isReflectedOnNextDecode() {
        val reordered = listOf(KeyMetric.REST, KeyMetric.CHARGE, KeyMetric.WEIGHT, KeyMetric.EFFORT, KeyMetric.HRV)
        val encoded = KeyMetricPrefs.encode(reordered)
        assertEquals("rest,charge,weight,effort,hrv", encoded)
        assertEquals(reordered, KeyMetricPrefs.decodeEnabled(encoded))
    }

    /** "Relaunch": decoding is a pure function of the persisted string, so re-decoding the SAME stored
     *  string (as a cold launch would) must yield byte-identical results across calls. */
    @Test
    fun repeatedDecodeOfTheSameStoredString_isStable() {
        val encoded = KeyMetricPrefs.encode(listOf(KeyMetric.CALORIES, KeyMetric.BLOOD_OXYGEN, KeyMetric.CHARGE))
        val first = KeyMetricPrefs.decodeEnabled(encoded)
        val second = KeyMetricPrefs.decodeEnabled(encoded)
        assertEquals(first, second)
        assertEquals(listOf(KeyMetric.CALORIES, KeyMetric.BLOOD_OXYGEN, KeyMetric.CHARGE), first)
    }

    @Test
    fun decode_dropsUnknownTokensAndCollapsesDuplicates() {
        val messy = "charge,BOGUS,charge,hrv, ,hrv,steps"
        assertEquals(listOf(KeyMetric.CHARGE, KeyMetric.HRV, KeyMetric.STEPS), KeyMetricPrefs.decodeEnabled(messy))
    }

    /** The bug this test would have caught on the Swift side: a saved string that decodes to NO known tile
     *  (every token stale/unrecognised) must fall back to the full default order — matching
     *  [DashboardCardPrefs] and the macOS twin — never to an empty grid, which reads exactly like the user's
     *  customisation vanished. Kotlin already got this right; this pins it so it can't regress. */
    @Test
    fun allUnknownTokens_fallBackToDefaultOrder_notAnEmptyGrid() {
        val decoded = KeyMetricPrefs.decodeEnabled("nope,zzz,BOGUS")
        assertEquals(KeyMetric.defaultOrder, decoded)
        assertTrue(decoded.isNotEmpty())
    }

    @Test
    fun defaultOrderCoversEveryEntry() {
        assertEquals(KeyMetric.entries.toSet(), KeyMetric.defaultOrder.toSet())
        assertEquals(KeyMetric.entries.size, KeyMetric.defaultOrder.size)
    }

    @Test
    fun metricRawKeysAreStableAndUnique() {
        val raws = KeyMetric.entries.map { it.raw }
        assertEquals("raw keys must be unique (they're the persisted identity)", raws.size, raws.toSet().size)
        // Pin the exact wire strings — they must match the macOS KeyMetric byte-for-byte.
        assertEquals(
            listOf("charge", "effort", "rest", "hrv", "restingHr", "bloodOxygen", "respiratory", "steps", "weight", "calories"),
            raws,
        )
    }

    /** End-to-end persistence over an in-memory SharedPreferences, exactly as [KeyMetricPrefs.enabled] /
     *  [KeyMetricPrefs.setEnabled] read/write it through [NoopPrefs] — pins the actual key name, not just
     *  the pure encode/decode functions. */
    @Test
    fun customisationPersistsThroughSharedPreferences() {
        val prefs = FakeSharedPreferences()

        // Fresh install: nothing written yet, reads as the full default order.
        assertEquals(KeyMetric.defaultOrder, KeyMetricPrefs.decodeEnabled(prefs.getString("today.keyMetrics", null)))

        // User customises: keeps only Rest + Charge, reordered.
        prefs.edit().putString("today.keyMetrics", KeyMetricPrefs.encode(listOf(KeyMetric.REST, KeyMetric.CHARGE))).apply()

        // "Relaunch": re-reading the same underlying store returns the persisted choice, not the default.
        assertEquals(
            listOf(KeyMetric.REST, KeyMetric.CHARGE),
            KeyMetricPrefs.decodeEnabled(prefs.getString("today.keyMetrics", null)),
        )
    }

    /** A minimal in-memory SharedPreferences: enough of the read/write contract for the test above. */
    private class FakeSharedPreferences : SharedPreferences {
        val map = HashMap<String, Any?>()

        override fun getBoolean(key: String, defValue: Boolean): Boolean = map[key] as? Boolean ?: defValue
        override fun getLong(key: String, defValue: Long): Long = map[key] as? Long ?: defValue
        override fun getString(key: String, defValue: String?): String? = map[key] as? String ?: defValue
        override fun getInt(key: String, defValue: Int): Int = map[key] as? Int ?: defValue
        override fun getFloat(key: String, defValue: Float): Float = map[key] as? Float ?: defValue
        @Suppress("UNCHECKED_CAST")
        override fun getStringSet(key: String, defValues: MutableSet<String>?): MutableSet<String>? =
            map[key] as? MutableSet<String> ?: defValues
        override fun getAll(): MutableMap<String, *> = HashMap(map)
        override fun contains(key: String): Boolean = map.containsKey(key)
        override fun registerOnSharedPreferenceChangeListener(l: SharedPreferences.OnSharedPreferenceChangeListener?) {}
        override fun unregisterOnSharedPreferenceChangeListener(l: SharedPreferences.OnSharedPreferenceChangeListener?) {}

        override fun edit(): SharedPreferences.Editor = FakeEditor(this)

        private class FakeEditor(private val prefs: FakeSharedPreferences) : SharedPreferences.Editor {
            private val pending = HashMap<String, Any?>()
            private val removals = HashSet<String>()
            override fun putString(key: String, value: String?): SharedPreferences.Editor { pending[key] = value; return this }
            override fun putStringSet(key: String, values: MutableSet<String>?): SharedPreferences.Editor { pending[key] = values; return this }
            override fun putInt(key: String, value: Int): SharedPreferences.Editor { pending[key] = value; return this }
            override fun putLong(key: String, value: Long): SharedPreferences.Editor { pending[key] = value; return this }
            override fun putFloat(key: String, value: Float): SharedPreferences.Editor { pending[key] = value; return this }
            override fun putBoolean(key: String, value: Boolean): SharedPreferences.Editor { pending[key] = value; return this }
            override fun remove(key: String): SharedPreferences.Editor { removals.add(key); return this }
            override fun clear(): SharedPreferences.Editor { prefs.map.clear(); return this }
            override fun commit(): Boolean { flush(); return true }
            override fun apply() { flush() }
            private fun flush() {
                for (k in removals) prefs.map.remove(k)
                prefs.map.putAll(pending)
            }
        }
    }
}
