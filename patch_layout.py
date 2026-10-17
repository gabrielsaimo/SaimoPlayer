import re

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoTV-Android/app/src/main/res/layout/item_evento.xml", "r") as f:
    content = f.read()

# Add canal info before eventoHorario
canal_xml = """
    <LinearLayout
        android:layout_width="100dp"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:layout_marginEnd="16dp"
        android:gravity="center">
        <ImageView
            android:id="@+id/imgCanalItem"
            android:layout_width="40dp"
            android:layout_height="40dp"
            android:scaleType="fitCenter" />
        <TextView
            android:id="@+id/textoCanalItem"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:textColor="#AAAAAA"
            android:textSize="12sp"
            android:maxLines="2"
            android:gravity="center"
            android:ellipsize="end" />
    </LinearLayout>
"""

content = content.replace('<TextView\n        android:id="@+id/eventoHorario"', canal_xml + '\n    <TextView\n        android:id="@+id/eventoHorario"')

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoTV-Android/app/src/main/res/layout/item_evento.xml", "w") as f:
    f.write(content)

