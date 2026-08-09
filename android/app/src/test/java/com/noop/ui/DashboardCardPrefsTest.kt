package com.noop.ui

import android.content.SharedPreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the "Your cards" dashboard persistence (WHOOP "My Dashboard"): the CONTRACT is that a customisation
 * (add a card, remove a card, reorder cards) survives relaunch. Twin of the macOS `DashboardCardPrefsTests`,
 * same "today.dashboardCards" key, same JSON-array encoding, same "unknown/all-unknown decodes to the
 * default selection, never to an empty dashboard" rule.
 */
class DashboardCardPrefsTest {

    @Test
    fun emptyOrUnset_yieldsDefaultSelection() {
        assertEquals(DashboardCard.defaultSelection, DashboardCardPrefs.decodeEnabled(null))
        assertEquals(DashboardCard.defaultSelection, DashboardCardPrefs.decodeEnabled(""))
        assertEquals(DashboardCard.defaultSelection, DashboardCardPrefs.decodeEnabled("   "))
    }

    /** "Add a card": a saved subset re-encoded with one more card appended must show the addition, in the
     *  position it was added, with everything else untouched, on the next decode. */
    @Test
    fun addingACard_isReflectedOnNextDecode() {
        val before = DashboardCardPrefs.decodeEnabled(DashboardCardPrefs.encode(listOf(DashboardCard.STRESS, DashboardCard.HRV)))
        assertEquals(listOf(DashboardCard.STRESS, DashboardCard.HRV), before)

        val after = DashboardCardPrefs.decodeEnabled(DashboardCardPrefs.encode(before + DashboardCard.HYDRATION))
        assertEquals(listOf(DashboardCard.STRESS, DashboardCard.HRV, DashboardCard.HYDRATION), after)
    }

    /** "Remove a card": a card dropped before encoding must not reappear on decode. */
    @Test
    fun removingACard_isReflectedOnNextDecode() {
        val full = listOf(DashboardCard.STRESS, DashboardCard.FITNESS_AGE, DashboardCard.VITALITY, DashboardCard.HRV, DashboardCard.RESTING_HR)
        val withoutVitality = full.filterNot { it == DashboardCard.VITALITY }
        val decoded = DashboardCardPrefs.decodeEnabled(DashboardCardPrefs.encode(withoutVitality))
        assertEquals(listOf(DashboardCard.STRESS, DashboardCard.FITNESS_AGE, DashboardCard.HRV, DashboardCard.RESTING_HR), decoded)
        assertFalse(decoded.contains(DashboardCard.VITALITY))
    }

    /** "Reorder cards": the saved ORDER, not just the saved SET, must round-trip exactly. */
    @Test
    fun reorderingCards_isReflectedOnNextDecode() {
        val reordered = listOf(DashboardCard.VITALITY, DashboardCard.STRESS, DashboardCard.COUPLED, DashboardCard.HRV)
        val encoded = DashboardCardPrefs.encode(reordered)
        assertEquals(reordered, DashboardCardPrefs.decodeEnabled(encoded))
    }

    /** "Relaunch": decoding is a pure function of the persisted string, so re-decoding the SAME stored
     *  string (as a cold launch would) must yield byte-identical results across calls. */
    @Test
    fun repeatedDecodeOfTheSameStoredString_isStable() {
        val encoded = DashboardCardPrefs.encode(listOf(DashboardCard.CALORIES, DashboardCard.SKIN_TEMP, DashboardCard.STRESS))
        val first = DashboardCardPrefs.decodeEnabled(encoded)
        val second = DashboardCardPrefs.decodeEnabled(encoded)
        assertEquals(first, second)
        assertEquals(listOf(DashboardCard.CALORIES, DashboardCard.SKIN_TEMP, DashboardCard.STRESS), first)
    }

    @Test
    fun decode_acceptsTheJsonArrayForm() {
        assertEquals(listOf(DashboardCard.HRV, DashboardCard.STRESS), DashboardCardPrefs.decodeEnabled("""["hrv","stress"]"""))
    }

    /** Legacy comma-joined form (predates the JSON-array switch) must still decode, so nobody's saved
     *  selection is silently wiped by a format change. */
    @Test
    fun decode_acceptsTheLegacyCommaJoinedForm() {
        assertEquals(listOf(DashboardCard.HRV, DashboardCard.STRESS), DashboardCardPrefs.decodeEnabled("hrv,stress"))
    }

    @Test
    fun decode_dropsUnknownIdsAndCollapsesDuplicates() {
        assertEquals(
            listOf(DashboardCard.HRV, DashboardCard.STRESS),
            DashboardCardPrefs.decodeEnabled("""["hrv","bogus","hrv","stress"]"""),
        )
    }

    /** A saved string that decodes to NO known card (every id stale/unrecognised) must fall back to the
     *  default selection, never to an empty dashboard. */
    @Test
    fun allUnknownIds_fallBackToDefaultSelection_notAnEmptyDashboard() {
        val decoded = DashboardCardPrefs.decodeEnabled("""["bogus","nope"]""")
        assertEquals(DashboardCard.defaultSelection, decoded)
        assertTrue(decoded.isNotEmpty())
    }

    @Test
    fun defaultSelectionCards_areAllKnown() {
        DashboardCard.defaultSelection.forEach { card ->
            assertTrue(DashboardCard.canonicalOrder.contains(card))
        }
    }

    @Test
    fun cardRawKeysAreStableAndUnique() {
        val raws = DashboardCard.entries.map { it.raw }
        assertEquals("raw keys must be unique (they're the persisted identity)", raws.size, raws.toSet().size)
        // Pin the exact wire strings — they must match the macOS DashboardCard byte-for-byte.
        assertEquals(
            listOf(
                "hrv", "restingHr", "respiratory", "steps", "stress", "fitnessAge", "vitality",
                "bloodOxygen", "skinTemp", "sleep", "calories", "hydration", "coupled",
            ),
            raws,
        )
    }

    /** End-to-end persistence over an in-memory SharedPreferences, exactly as [DashboardCardPrefs.enabled] /
     *  [DashboardCardPrefs.setEnabled] read/write it through [NoopPrefs] — pins the actual key name, not
     *  just the pure encode/decode functions. */
    @Test
    fun customisationPersistsThroughSharedPreferences() {
        val prefs = FakeSharedPreferences()

        // Fresh install: nothing written yet, reads as the default selection.
        assertEquals(DashboardCard.defaultSelection, DashboardCardPrefs.decodeEnabled(prefs.getString("today.dashboardCards", null)))

        // User customises: adds the optional Coupled-view card and drops Vitality.
        val chosen = listOf(DashboardCard.STRESS, DashboardCard.FITNESS_AGE, DashboardCard.HRV, DashboardCard.RESTING_HR, DashboardCard.COUPLED)
        prefs.edit().putString("today.dashboardCards", DashboardCardPrefs.encode(chosen)).apply()

        // "Relaunch": re-reading the same underlying store returns the persisted choice, not the default.
        assertEquals(chosen, DashboardCardPrefs.decodeEnabled(prefs.getString("today.dashboardCards", null)))
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
